# frozen_string_literal: true

require 'json'
require 'open3'
require 'fileutils'
require 'timeout'

SOCKS_PORT = 2081
HTTP_PORT = 9001
HEALTH_INTERVAL = 15
FAILURES_BEFORE_RESTART = 2
RESTART_COOLDOWN = 60
PROBE_URLS = [
  'http://cp.cloudflare.com/generate_204',
  'http://connectivitycheck.gstatic.com/generate_204'
].freeze

RESOURCES = ENV['AUTO_XRAY_RESOURCES'].to_s.empty? ? File.expand_path(__dir__) : ENV['AUTO_XRAY_RESOURCES']
CORE_HELPER = File.join(RESOURCES, 'auto-xray-core-helper.rb')
XRAY = File.join(RESOURCES, 'xray')

HOME_DIR = Dir.home
SUPPORT = File.join(HOME_DIR, 'Library', 'Application Support', 'AUTO Xray')
STATE = File.join(SUPPORT, 'State')
LOG_DIR = File.join(HOME_DIR, 'Library', 'Logs', 'AUTO Xray')
RUNTIME_CONFIG = File.join(STATE, 'runtime_config.json')
PID_FILE = File.join(STATE, 'xray.pid')
HEALTH_FILE = File.join(STATE, 'supervisor-health.json')
LOCK_FILE = File.join(STATE, 'supervisor.lock')
RUNTIME_LOG = File.join(LOG_DIR, 'runtime.log')

FileUtils.mkdir_p(STATE)
FileUtils.mkdir_p(LOG_DIR)

def run_cmd(cmd, timeout_sec = nil)
  out = ''
  code = 999
  begin
    runner = proc do
      out, st = Open3.capture2e(*cmd)
      code = st.exitstatus || 0
    end
    timeout_sec ? Timeout.timeout(timeout_sec, &runner) : runner.call
  rescue Timeout::Error
    out = "#{out}\ntimeout"
    code = 997
  rescue StandardError => e
    out = e.message
    code = 999
  end
  [code, out]
end

def helper(args)
  env = {
    'LC_ALL' => 'en_US.UTF-8',
    'LANG' => 'en_US.UTF-8',
    'AUTO_XRAY_RESOURCES' => RESOURCES
  }
  out, err, st = Open3.capture3(env, '/usr/bin/ruby', '-EUTF-8:UTF-8', CORE_HELPER, *args)
  [st.exitstatus || 0, out.to_s, err.to_s]
rescue StandardError => e
  [999, '', e.message]
end

def print_helper_result(rc, out, err)
  $stdout.write(out) unless out.empty?
  $stderr.write(err) unless err.empty?
  exit(rc.zero? ? 0 : rc)
end

def with_runtime_lock(nonblocking: false)
  lock = File.open(LOCK_FILE, File::RDWR | File::CREAT, 0o600)
  flags = File::LOCK_EX
  flags |= File::LOCK_NB if nonblocking
  acquired = lock.flock(flags)
  return nil unless acquired
  begin
    yield
  ensure
    lock.flock(File::LOCK_UN) rescue nil
    lock.close rescue nil
  end
end

def probe(index = 0)
  url = PROBE_URLS[index.to_i % PROBE_URLS.length]
  run_cmd([
    '/usr/bin/curl',
    '--silent', '--show-error',
    '--connect-timeout', '3',
    '--max-time', '5',
    '--socks5-hostname', "127.0.0.1:#{SOCKS_PORT}",
    '-o', '/dev/null',
    '-w', '%{http_code} %{time_total}',
    url
  ], 7)
end

def probe_ok?(rc, out)
  return false unless rc.zero?
  code = out.to_s.strip.split.first.to_s
  code == '204' || code == '200'
end

def log(message)
  File.open(RUNTIME_LOG, 'a') do |f|
    f.puts("[AUTO Xray supervisor] #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{message}")
  end
rescue StandardError
end

def process_alive?(pid)
  return false unless pid.to_i > 0
  Process.kill(0, pid.to_i)
  true
rescue StandardError
  false
end

def process_command(pid)
  rc, out = run_cmd(['/bin/ps', '-p', pid.to_i.to_s, '-o', 'command='], 5)
  rc.zero? ? out.strip : ''
end

def our_xray_process?(pid)
  cmd = process_command(pid)
  !cmd.empty? && (cmd.include?(RUNTIME_CONFIG) || cmd.include?(XRAY) || cmd.include?('AUTO Xray.app/Contents/Resources/xray'))
end

def listener_pids(port)
  rc, out = run_cmd(['/usr/sbin/lsof', '-nP', '-tiTCP:' + port.to_i.to_s, '-sTCP:LISTEN'], 5)
  return [] unless rc.zero?
  out.lines.map { |line| line.to_i }.select { |pid| pid > 0 }.uniq
end

def core_running?
  return false unless File.file?(PID_FILE)
  process_alive?(File.read(PID_FILE).to_i)
rescue StandardError
  false
end

def network_services
  rc, out = run_cmd(['/usr/sbin/networksetup', '-listallnetworkservices'], 10)
  return [] unless rc.zero?

  out.lines.map(&:strip).reject do |line|
    line.empty? || line.start_with?('An asterisk')
  end.map { |line| line.sub(/^\*/, '').strip }.reject(&:empty?)
end

def proxy_state(service, get_flag)
  rc, out = run_cmd(['/usr/sbin/networksetup', get_flag, service], 10)
  return nil unless rc.zero?

  state = { 'enabled' => false, 'server' => '', 'port' => 0 }
  out.each_line do |line|
    next unless line.include?(':')
    key, value = line.split(':', 2).map(&:strip)
    case key.downcase
    when 'enabled' then state['enabled'] = value.casecmp('yes').zero?
    when 'server' then state['server'] = value
    when 'port' then state['port'] = value.to_i
    end
  end
  state
end

def disable_stale_auto_proxies
  return false if core_running?

  changed = false
  specs = [
    ['-getwebproxy', '-setwebproxystate', HTTP_PORT, 'HTTP'],
    ['-getsecurewebproxy', '-setsecurewebproxystate', HTTP_PORT, 'HTTPS'],
    ['-getsocksfirewallproxy', '-setsocksfirewallproxystate', SOCKS_PORT, 'SOCKS']
  ]

  network_services.each do |service|
    specs.each do |get_flag, set_flag, expected_port, label|
      state = proxy_state(service, get_flag)
      next unless state && state['enabled'] && state['server'] == '127.0.0.1' && state['port'] == expected_port

      rc, out = run_cmd(['/usr/sbin/networksetup', set_flag, service, 'off'], 10)
      if rc.zero?
        changed = true
        log("disabled stale #{label} proxy on #{service}")
      else
        log("could not disable stale #{label} proxy on #{service}: #{out.to_s.strip}")
      end
    end
  end

  changed
rescue StandardError => e
  log("stale proxy cleanup failed: #{e.message}")
  false
end

def stop_pid(pid)
  return unless process_alive?(pid)
  Process.kill('TERM', pid) rescue nil
  24.times do
    break unless process_alive?(pid)
    sleep 0.25
  end
  Process.kill('KILL', pid) rescue nil if process_alive?(pid)
  Process.wait(pid) rescue nil
rescue StandardError
end

def cleanup_orphan_runtime
  pids = (listener_pids(SOCKS_PORT) + listener_pids(HTTP_PORT)).uniq
  ours = pids.select { |pid| our_xray_process?(pid) }
  return if ours.empty?

  log("cleaning orphan Xray listeners: #{ours.join(',')}")
  ours.each { |pid| stop_pid(pid) }

  20.times do
    remaining = (listener_pids(SOCKS_PORT) + listener_pids(HTTP_PORT)).uniq.select { |pid| our_xray_process?(pid) }
    return if remaining.empty?
    sleep 0.25
  end
rescue StandardError => e
  log("orphan runtime cleanup failed: #{e.message}")
end

def patch_runtime_probe
  return unless File.file?(RUNTIME_CONFIG)
  cfg = JSON.parse(File.read(RUNTIME_CONFIG, encoding: 'UTF-8'))
  if cfg['observatory'].is_a?(Hash)
    # AUTO groups must probe candidate outbounds concurrently. With sequential
    # probing, one dead first node can delay discovery of a healthy sibling long
    # enough for startup to fail even though the group contains a usable node.
    cfg['observatory']['probeURL'] = PROBE_URLS.first
    cfg['observatory']['enableConcurrency'] = true
  end
  File.write(RUNTIME_CONFIG, JSON.pretty_generate(cfg))
rescue StandardError => e
  log("could not patch runtime probe: #{e.message}")
end

def fallback_start
  raise 'runtime config is missing' unless File.file?(RUNTIME_CONFIG)
  raise 'Xray core is missing' unless File.executable?(XRAY)

  patch_runtime_probe
  last_error = ''

  cfg = JSON.parse(File.read(RUNTIME_CONFIG, encoding: 'UTF-8')) rescue {}
  auto_group = cfg['observatory'].is_a?(Hash)

  2.times do |attempt|
    cleanup_orphan_runtime

    f = File.open(RUNTIME_LOG, 'a')
    f.puts("\n=== SUPERVISOR START #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} attempt=#{attempt + 1} ===")
    f.flush

    pid = Process.spawn(XRAY, 'run', '-config', RUNTIME_CONFIG, out: f, err: f, pgroup: true)
    sleep(auto_group ? 2.5 : 0.75)

    unless process_alive?(pid)
      last_error = 'Xray stopped immediately'
      f.close
      cleanup_orphan_runtime
      sleep 0.5
      next
    end

    ok = false
    probe_count = auto_group ? 3 : 2
    probe_count.times do |i|
      rc, out = probe(i)
      if probe_ok?(rc, out)
        ok = true
        last_error = out.to_s.strip
        break
      end
      last_error = out.to_s.strip
      sleep 0.75 if i < probe_count - 1
    end

    if ok
      File.write(PID_FILE, pid.to_s)
      File.chmod(0o600, PID_FILE) rescue nil
      f.puts("[AUTO Xray supervisor] startup probe OK: #{last_error}")
      f.close

      rc, out, err = helper(['ensure-proxy'])
      raise(err.empty? ? out : err) unless rc.zero?

      log('fallback start succeeded')
      return true
    end

    f.puts("[AUTO Xray supervisor] startup probe failed: #{last_error}")
    f.close
    stop_pid(pid)
    cleanup_orphan_runtime
    break
  end

  raise "proxy probe failed after automatic retry: #{last_error}"
end

def read_menu_state
  rc, out, = helper(['menu-state'])
  return nil unless rc.zero?
  parsed = JSON.parse(out)
  parsed.is_a?(Hash) ? parsed : nil
rescue StandardError
  nil
end

def selected_manual_mode?
  state = read_menu_state
  mode = state && state['mode']
  mode.is_a?(Hash) && mode['type'] == 'manual'
rescue StandardError
  false
end

def resilient_start(allow_fallback: nil)
  # A manual mode has exactly one remote endpoint. Retrying the same dead node
  # through supervisor fallback only multiplies the wait without adding a new
  # candidate. AUTO groups keep recovery because another sibling may work.
  allow_fallback = !selected_manual_mode? if allow_fallback.nil?

  rc, out, err = helper(['start'])
  return [rc, out, err] if rc.zero?

  first_error = (err.empty? ? out : err).strip
  unless allow_fallback
    log("manual start failed; same-node recovery skipped: #{first_error}")
    if !listener_pids(SOCKS_PORT).empty? || !listener_pids(HTTP_PORT).empty?
      cleanup_orphan_runtime
    end
    return [rc, out, err]
  end

  log("normal AUTO start failed, trying supervisor recovery: #{first_error}")

  begin
    cleanup_orphan_runtime
    fallback_start
    [0, "ON\n", '']
  rescue StandardError => e
    helper(['stop'])
    cleanup_orphan_runtime
    disable_stale_auto_proxies
    [50, '', "ERROR: #{e.message}\n"]
  end
end

def mode_args(mode)
  return nil unless mode.is_a?(Hash)
  if mode['type'] == 'manual'
    node = mode['node'].to_s
    node.empty? ? nil : ['mode', 'manual', node]
  else
    group = mode['group'].to_s
    group = 'RF' if group.empty?
    ['mode', 'auto', group]
  end
end

def resilient_mode(args)
  state = read_menu_state
  return helper(['mode'] + args) unless state && state['on']

  old_mode = state['mode'].is_a?(Hash) ? state['mode'] : { 'type' => 'auto', 'group' => 'RF' }
  old_args = mode_args(old_mode)
  target = args.join(' ')
  target_manual = args.first == 'manual'
  log("foreground mode switch started: #{target}")

  src0, sout0, serr0 = helper(['stop'])
  unless src0.zero?
    cleanup_orphan_runtime
    disable_stale_auto_proxies
    return [src0, sout0, serr0]
  end
  if !listener_pids(SOCKS_PORT).empty? || !listener_pids(HTTP_PORT).empty?
    cleanup_orphan_runtime
  end

  mrc, mout, merr = helper(['mode'] + args)
  unless mrc.zero?
    return [mrc, mout, merr]
  end

  src, sout, serr = resilient_start(allow_fallback: !target_manual)
  if src.zero?
    log("foreground mode switch succeeded: #{target}")
    return [0, '', '']
  end

  target_error = (serr.empty? ? sout : serr).strip
  log("foreground mode switch failed: #{target}: #{target_error}")

  # Core helper restores the saved system proxy state on a failed start. Avoid
  # an expensive all-services stale-proxy scan before rollback; keep the broad
  # cleanup only if rollback itself fails.
  helper(['stop'])
  if !listener_pids(SOCKS_PORT).empty? || !listener_pids(HTTP_PORT).empty?
    cleanup_orphan_runtime
  end

  rollback_error = ''
  if old_args
    rmc, rmout, rmerr = helper(old_args)
    if rmc.zero?
      rrc, rrout, rrerr = resilient_start
      if rrc.zero?
        log('foreground mode rollback succeeded')
      else
        rollback_error = (rrerr.empty? ? rrout : rrerr).strip
      end
    else
      rollback_error = (rmerr.empty? ? rmout : rmerr).strip
    end
  else
    rollback_error = 'previous mode unavailable'
  end

  unless rollback_error.empty?
    helper(['stop'])
    cleanup_orphan_runtime
    disable_stale_auto_proxies
    log("foreground mode rollback failed: #{rollback_error}")
  end

  message = "ERROR: Could not switch mode: #{target_error}"
  message += " (rollback failed: #{rollback_error})" unless rollback_error.empty?
  [50, '', message + "\n"]
end

def read_health
  return { 'lastProbe' => 0, 'failures' => 0, 'lastRestart' => 0 } unless File.file?(HEALTH_FILE)
  h = JSON.parse(File.read(HEALTH_FILE, encoding: 'UTF-8')) rescue {}
  {
    'lastProbe' => h['lastProbe'].to_i,
    'failures' => h['failures'].to_i,
    'lastRestart' => h['lastRestart'].to_i
  }
end

def write_health(h)
  File.write(HEALTH_FILE, JSON.pretty_generate(h))
rescue StandardError
end

def supervisor_health
  rc, out, err = helper(['ensure-proxy'])
  return [rc, out, err] unless rc.zero?
  if out.include?('IDLE')
    disable_stale_auto_proxies
    return [0, out, err]
  end

  now = Time.now.to_i
  h = read_health
  return [0, out, err] if now - h['lastProbe'] < HEALTH_INTERVAL

  h['lastProbe'] = now
  prc, pout = probe(h['failures'])

  if probe_ok?(prc, pout)
    log("connectivity recovered without restart: #{pout.strip}") if h['failures'] > 0
    h['failures'] = 0
    write_health(h)
    return [0, out, err]
  end

  h['failures'] += 1
  log("health probe failed ##{h['failures']}: #{pout.to_s.strip}")

  if h['failures'] < FAILURES_BEFORE_RESTART || now - h['lastRestart'] < RESTART_COOLDOWN
    write_health(h)
    return [0, out, err]
  end

  h['lastRestart'] = now
  write_health(h)
  log('automatic recovery started')

  helper(['stop'])
  cleanup_orphan_runtime
  disable_stale_auto_proxies
  src, sout, serr = resilient_start

  if src.zero?
    h['failures'] = 0
    h['lastProbe'] = Time.now.to_i
    write_health(h)
    log('automatic recovery succeeded')
    [0, "OK\n", '']
  else
    log("automatic recovery failed: #{serr.empty? ? sout : serr}")
    [0, "IDLE\n", '']
  end
end

cmd = ARGV.shift.to_s
args = ARGV.dup

case cmd
when 'start'
  result = with_runtime_lock { resilient_start }
  print_helper_result(*result)
when 'ensure-proxy'
  result = with_runtime_lock(nonblocking: true) { supervisor_health }
  result ||= [0, "BUSY\n", '']
  print_helper_result(*result)
when 'stop'
  result = with_runtime_lock do
    File.delete(HEALTH_FILE) rescue nil
    rc, out, err = helper(['stop'] + args)
    if rc.zero?
      if !listener_pids(SOCKS_PORT).empty? || !listener_pids(HTTP_PORT).empty?
        cleanup_orphan_runtime
      end
    else
      cleanup_orphan_runtime
      disable_stale_auto_proxies
    end
    [rc, out, err]
  end
  print_helper_result(*result)
when 'mode'
  result = with_runtime_lock { resilient_mode(args) }
  print_helper_result(*result)
else
  mutating = %w[update bootstrap install-login-agent uninstall-login-agent].include?(cmd)
  result = if mutating
             with_runtime_lock { helper([cmd] + args) }
           else
             helper([cmd] + args)
           end
  print_helper_result(*result)
end

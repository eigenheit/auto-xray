# frozen_string_literal: true

require 'json'
require 'base64'
require 'digest'
require 'fileutils'
require 'uri'
require 'securerandom'
require 'open3'
require 'timeout'

HTTP_PORT = 9001
SOCKS_PORT = 2081
PROBE_URL = 'https://www.gstatic.com/generate_204'

WARNING_MARKERS = [
  'ключ не поддерживается', 'новый ключ', 'обратитесь в поддержку',
  'key not supported', 'new key', 'contact support'
].freeze

REQUEST_PROFILES = [
  ['Happ_exact_hwid_only', 'Happ/1.0', 'hwid'],
  ['v2RayTun_exact', 'v2RayTun/2.0', 'hwid'],
  ['v2RayTun_with_os', 'v2RayTun/2.0', 'device'],
  ['Happ_with_os', 'Happ/1.0', 'device']
].freeze

def paths
  home = Dir.home
  support = File.join(home, 'Library', 'Application Support', 'AUTO Xray')
  config = File.join(support, 'Config')
  state = File.join(support, 'State')
  data = File.join(support, 'Data')
  logs = File.join(home, 'Library', 'Logs', 'AUTO Xray')
  {
    home: home, support: support, config: config, state: state, data: data, logs: logs,
    raw: File.join(data, 'raw'), json_all: File.join(data, 'json-all'),
    json_unique: File.join(data, 'json-unique'), exports: File.join(data, 'exports'),
    sub_url: File.join(config, 'subscription_url.txt'), hwid: File.join(config, 'hwid.txt'),
    proxy_state: File.join(state, 'proxy_state.json'), pid: File.join(state, 'xray.pid'),
    mode: File.join(state, 'mode.json'), nodes: File.join(data, 'nodes.json'),
    runtime_config: File.join(state, 'runtime_config.json'), status: File.join(state, 'status.txt'),
    runtime_log: File.join(logs, 'runtime.log'), summary: File.join(data, 'SUMMARY.txt'),
    probe_report: File.join(data, 'probe-report.txt'), duplicates: File.join(data, 'DUPLICATES.txt'),
    vless_links: File.join(data, 'vless-links.txt'),
    combined: File.join(data, 'exports', 'V2RayXS_IMPORT_ALL.json')
  }
end

P = paths

def ensure_dirs
  [P[:config], P[:state], P[:data], P[:raw], P[:json_all], P[:json_unique], P[:exports], P[:logs]].each do |d|
    FileUtils.mkdir_p(d)
  end
end

ensure_dirs

def run_cmd(cmd, timeout_sec = nil)
  output = ''
  status = 999
  begin
    runner = proc do
      output, st = Open3.capture2e(*cmd)
      status = st.exitstatus || 0
    end
    if timeout_sec
      Timeout.timeout(timeout_sec, &runner)
    else
      runner.call
    end
  rescue Timeout::Error
    output = "#{output}\ntimeout"
    status = 997
  rescue StandardError => e
    output = e.message
    status = 999
  end
  [status, output]
end

def stable_hwid
  if File.file?(P[:hwid])
    value = File.read(P[:hwid], encoding: 'UTF-8').strip
    return value unless value.empty?
  end
  value = SecureRandom.uuid
  File.write(P[:hwid], value + "\n")
  File.chmod(0o600, P[:hwid]) rescue nil
  value
end

def mac_version
  rc, out = run_cmd(['/usr/bin/sw_vers', '-productVersion'], 5)
  rc.zero? ? out.strip : 'unknown'
end

def model_identifier
  rc, out = run_cmd(['/usr/sbin/system_profiler', 'SPHardwareDataType'], 15)
  return 'Mac' unless rc.zero?
  line = out.lines.find { |x| x.include?('Model Identifier:') }
  line ? line.split(':', 2)[1].to_s.strip : 'Mac'
end

def safe_name(value)
  s = value.to_s
  begin
    s = URI.decode_www_form_component(s)
  rescue StandardError
  end
  s = s.strip.gsub(/[\\\/:*?"<>|]+/, '_').gsub(/\s+/, ' ')
  s = 'node' if s.empty?
  s.each_char.take(100).join
end

def deep_copy(obj)
  JSON.parse(JSON.generate(obj))
end

def qput(q, key, value)
  return if value.nil?
  val = value.is_a?(TrueClass) || value.is_a?(FalseClass) ? (value ? 'true' : 'false') : value.to_s
  q[key] = val unless val.empty?
end

def url_query(q)
  URI.encode_www_form(q)
end

def outbound_to_vless(outbound, profile_name = '')
  return [] unless outbound.is_a?(Hash) && outbound['protocol'] == 'vless'
  settings = outbound['settings'].is_a?(Hash) ? outbound['settings'] : {}
  stream = outbound['streamSettings'].is_a?(Hash) ? outbound['streamSettings'] : {}
  network = stream['network'].to_s.empty? ? 'tcp' : stream['network'].to_s
  security = stream['security'].to_s.empty? ? 'none' : stream['security'].to_s
  tag = outbound['tag'].to_s
  tag = profile_name.to_s if tag.empty?
  tag = 'VLESS' if tag.empty?
  tag = profile_name.to_s if !profile_name.to_s.empty? && %w[main proxy outbound vless].include?(tag.downcase)

  links = []
  Array(settings['vnext']).each do |vnext|
    next unless vnext.is_a?(Hash)
    address = vnext['address'].to_s
    port = vnext['port'].to_i
    next if address.empty? || port <= 0
    Array(vnext['users']).each do |user|
      next unless user.is_a?(Hash)
      uid = user['id'].to_s
      next if uid.empty?
      q = {}
      qput(q, 'encryption', user['encryption'].to_s.empty? ? 'none' : user['encryption'])
      qput(q, 'flow', user['flow'])
      qput(q, 'type', network)
      qput(q, 'security', security)

      if security == 'reality'
        rs = stream['realitySettings'].is_a?(Hash) ? stream['realitySettings'] : {}
        qput(q, 'sni', rs['serverName'])
        qput(q, 'fp', rs['fingerprint'])
        qput(q, 'pbk', rs['publicKey'])
        qput(q, 'sid', rs['shortId'])
        qput(q, 'spx', rs['spiderX'])
        qput(q, 'alpn', Array(rs['alpn']).join(',')) unless Array(rs['alpn']).empty?
      elsif security == 'tls'
        ts = stream['tlsSettings'].is_a?(Hash) ? stream['tlsSettings'] : {}
        qput(q, 'sni', ts['serverName'])
        qput(q, 'fp', ts['fingerprint'])
      end

      if network == 'grpc'
        gs = stream['grpcSettings'].is_a?(Hash) ? stream['grpcSettings'] : {}
        qput(q, 'serviceName', gs['serviceName'])
        qput(q, 'authority', gs['authority'])
        mode = gs['mode'].to_s
        mode = 'multi' if mode.empty? && gs['multiMode'] == true
        qput(q, 'mode', mode)
      elsif network == 'ws'
        ws = stream['wsSettings'].is_a?(Hash) ? stream['wsSettings'] : {}
        qput(q, 'path', ws['path'])
        headers = ws['headers'].is_a?(Hash) ? ws['headers'] : {}
        qput(q, 'host', headers['Host'] || headers['host'])
      end

      fragment = URI.encode_www_form_component(tag).gsub('+', '%20')
      links << "vless://#{uid}@#{address}:#{port}?#{url_query(q)}##{fragment}"
    end
  end
  links
end

def scan_json(value, inherited_name = '', links = [])
  case value
  when Hash
    profile = value['remarks'] || value['name'] || value['profileTitle'] || inherited_name
    Array(value['outbounds']).each do |o|
      links.concat(outbound_to_vless(o, profile.to_s)) if o.is_a?(Hash)
    end
    %w[config data profile profiles items].each do |key|
      scan_json(value[key], profile.to_s, links) if value.key?(key)
    end
  when Array
    value.each { |item| scan_json(item, inherited_name, links) }
  end
  links
end

def base64_candidates(raw)
  compact = raw.to_s.gsub(/\s+/, '')
  return [] if compact.empty?
  compact += '=' until (compact.length % 4).zero?
  out = []
  begin out << Base64.strict_decode64(compact); rescue StandardError; end
  begin out << Base64.urlsafe_decode64(compact); rescue StandardError; end
  out.uniq
end

def extract_vless(text)
  found = []
  text.to_s.each_line do |line|
    line = line.strip
    found << line if line.downcase.start_with?('vless://')
  end
  begin
    found.concat(scan_json(JSON.parse(text)))
  rescue StandardError
  end
  base64_candidates(text).each do |decoded|
    decoded.each_line do |line|
      line = line.strip
      found << line if line.downcase.start_with?('vless://')
    end
    begin
      found.concat(scan_json(JSON.parse(decoded)))
    rescue StandardError
    end
  end
  seen = {}
  found.select { |x| !seen[x] && (seen[x] = true) }
end

def decoded_fragment(link)
  uri = URI.parse(link)
  frag = uri.fragment.to_s
  URI.decode_www_form_component(frag).downcase
rescue StandardError
  ''
end

def endpoint_signature(link)
  uri = URI.parse(link)
  uri.host.to_s.downcase + ':' + (uri.port || 0).to_s
rescue StandardError
  link
end

def warning_count(links)
  links.count do |link|
    name = decoded_fragment(link)
    WARNING_MARKERS.any? { |m| name.include?(m) }
  end
end

def score_links(links)
  return -100_000 if links.empty?
  endpoints = links.map { |x| endpoint_signature(x) }.uniq
  score = links.length * 20 + endpoints.length * 30 - warning_count(links) * 200
  score += 300 if endpoints.length >= 3
  score += 150 if links.length >= 5
  score
end

def curl_fetch(sub_url, ua, kind, hwid)
  args = [
    '/usr/bin/curl', '-L', '--compressed', '--silent', '--show-error', '--fail',
    '--connect-timeout', '35', '--max-time', '35', '-A', ua,
    '-H', 'Accept: application/json, text/plain, */*', '-H', "x-hwid: #{hwid}"
  ]
  if kind == 'device'
    args += ['-H', 'x-device-os: macOS', '-H', "x-ver-os: #{mac_version}", '-H', "x-device-model: #{model_identifier}"]
  end
  args << sub_url
  run_cmd(args, 40)
end

def vless_to_outbound(link, index)
  uri = URI.parse(link)
  raise 'not vless' unless uri.scheme.to_s.downcase == 'vless'
  params = URI.decode_www_form(uri.query.to_s).group_by(&:first).transform_values { |v| v.map(&:last) }
  first = lambda { |key, default = ''| params[key] && params[key][0] ? params[key][0] : default }
  name = safe_name(uri.fragment.to_s)
  tag = format('node-%03d %s', index, name)
  uid = uri.user.to_s
  encryption = first.call('encryption', 'none')
  user = { 'id' => uid, 'encryption' => encryption }
  flow = first.call('flow', '')
  user['flow'] = flow unless flow.empty?
  network = first.call('type', 'tcp')
  security = first.call('security', 'none')
  stream = { 'network' => network, 'security' => security }

  if security == 'reality'
    rs = {}
    { 'serverName' => 'sni', 'fingerprint' => 'fp', 'publicKey' => 'pbk', 'shortId' => 'sid', 'spiderX' => 'spx' }.each do |dst, src|
      val = first.call(src, '')
      rs[dst] = val unless val.empty?
    end
    alpn = first.call('alpn', '')
    rs['alpn'] = alpn.split(',') unless alpn.empty?
    stream['realitySettings'] = rs
  elsif security == 'tls'
    ts = {}
    sni = first.call('sni', '')
    fp = first.call('fp', '')
    ts['serverName'] = sni unless sni.empty?
    ts['fingerprint'] = fp unless fp.empty?
    stream['tlsSettings'] = ts
  end

  if network == 'grpc'
    service = first.call('serviceName', '')
    service = first.call('service_name', '') if service.empty?
    service = first.call('service-name', '') if service.empty?
    service = first.call('path', '') if service.empty?
    gs = { 'serviceName' => service, 'multiMode' => first.call('mode', '') == 'multi' }
    authority = first.call('authority', '')
    gs['authority'] = authority unless authority.empty?
    stream['grpcSettings'] = gs
  elsif network == 'ws'
    path = first.call('path', '/')
    ws = { 'path' => path, 'headers' => {} }
    host = first.call('host', '')
    ws['headers']['Host'] = host unless host.empty?
    stream['wsSettings'] = ws
  elsif network == 'tcp'
    ht = first.call('headerType', '')
    ht = first.call('header', '') if ht.empty?
    ht = 'none' if ht.empty?
    stream['tcpSettings'] = { 'header' => { 'type' => ht } }
  end

  port = uri.port || 443
  out = {
    'protocol' => 'vless', 'tag' => tag,
    'settings' => { 'vnext' => [{ 'address' => uri.host.to_s, 'port' => port, 'users' => [user] }] },
    'streamSettings' => stream
  }
  [out, name]
end

def fingerprint(outbound)
  obj = deep_copy(outbound)
  obj.delete('tag')
  Digest::SHA256.hexdigest(JSON.generate(obj.sort.to_h))
end

def endpoint(outbound)
  v = outbound.dig('settings', 'vnext', 0) || {}
  [v['address'].to_s, (v['port'] || 443).to_i]
end

def classify(name, address)
  n = name.to_s.downcase
  a = address.to_s.downcase
  return ['RF', 'RF'] if n == 'llp' || n.match?(/^lte(?:-\d+)?$/)
  eu = n.start_with?('eu') || n.include?('нидерланд') || n.include?('герман') || n.include?('великобрит') ||
       n.include?('netherlands') || n.include?('germany') || n.include?('united kingdom') ||
       %w[nlc. nlm. dem. ukm. bri.].any? { |pfx| a.start_with?(pfx) }
  eu ? ['EU', 'EU'] : ['WORLD', 'World']
end

def geo_label(name, address)
  a = address.to_s.downcase
  return 'Netherlands' if a.start_with?('nlc.') || a.start_with?('nlm.')
  return 'Germany' if a.start_with?('dem.')
  return 'UK' if a.start_with?('ukm.') || a.start_with?('bri.')
  return 'Turkey' if a.start_with?('trj.')
  name
end

def reset_dir(path)
  FileUtils.rm_rf(path)
  FileUtils.mkdir_p(path)
end

def write_json(path, obj)
  File.write(path, JSON.pretty_generate(obj))
  File.chmod(0o600, path) rescue nil
end

def update_subscription(new_url = nil)
  unless new_url.to_s.empty?
    File.write(P[:sub_url], new_url.strip + "\n")
    File.chmod(0o600, P[:sub_url]) rescue nil
  end
  raise 'NO_URL' unless File.file?(P[:sub_url]) && !File.read(P[:sub_url]).strip.empty?
  sub_url = File.read(P[:sub_url]).strip

  [P[:raw], P[:json_all], P[:json_unique]].each { |d| reset_dir(d) }
  FileUtils.mkdir_p(P[:exports])

  hwid = stable_hwid
  candidates = []
  report = []
  REQUEST_PROFILES.each_with_index do |(name, ua, kind), idx|
    rc, raw = curl_fetch(sub_url, ua, kind, hwid)
    unless rc.zero?
      report << "#{name}: ERROR #{raw.strip}"
      next
    end
    File.write(File.join(P[:raw], format('%02d_%s.txt', idx + 1, name)), raw)
    links = extract_vless(raw)
    warnings = warning_count(links)
    score = score_links(links)
    report << "#{name}: bytes=#{raw.bytesize} vless=#{links.length} warnings=#{warnings} score=#{score}"
    candidates << [score, name, raw, links, warnings]
  end

  if candidates.empty?
    File.write(P[:probe_report], report.join("\n") + "\n")
    raise 'FETCH_FAILED'
  end

  best = candidates.max_by { |x| x[0] }
  _score, profile_name, raw, links, warnings = best
  raise 'NO_USABLE_NODES' if links.empty? || warnings == links.length

  File.write(P[:vless_links], links.join("\n") + "\n")
  entries = []
  links.each_with_index do |link, i|
    begin
      out, name = vless_to_outbound(link, i + 1)
      write_json(File.join(P[:json_all], format('%03d - %s.json', i + 1, safe_name(name))), out)
      entries << { source: i + 1, name: name, out: out, fp: fingerprint(out) }
    rescue StandardError
    end
  end

  first = {}
  aliases = Hash.new { |h, k| h[k] = [] }
  unique = []
  entries.each do |en|
    aliases[en[:fp]] << en[:name]
    unless first.key?(en[:fp])
      first[en[:fp]] = en
      unique << en
    end
  end

  counts = { 'RF' => 0, 'EU' => 0, 'WORLD' => 0 }
  nodes = []
  combined = { 'outbounds' => [] }
  index_lines = []
  dup_lines = aliases.values.select { |names| names.length > 1 }.map { |names| names.join(' == ') }

  unique.each_with_index do |en, i|
    out = deep_copy(en[:out])
    addr, port = endpoint(out)
    group, label = classify(en[:name], addr)
    counts[group] += 1
    regional_no = counts[group]
    display = geo_label(en[:name], addr)
    if group != 'RF'
      same = unique.count do |z|
        za, = endpoint(z[:out])
        zg, = classify(z[:name], za)
        zg == group && geo_label(z[:name], za) == display
      end
      display = "#{display} #{regional_no}" if same > 1
    end
    node_id = format('%s-%02d', group.downcase, regional_no)
    tag = "ax-#{node_id} #{display}"
    out['tag'] = tag
    write_json(File.join(P[:json_unique], format('%03d - %s.json', i + 1, safe_name(display))), out)
    nodes << {
      'id' => node_id, 'group' => group, 'groupLabel' => label, 'name' => display,
      'address' => addr, 'port' => port, 'tag' => tag, 'outbound' => out, 'aliases' => aliases[en[:fp]]
    }
    combined['outbounds'] << out
    index_lines << "#{node_id} -> #{display} -> #{addr}:#{port}"
  end

  File.write(File.join(P[:json_unique], 'INDEX.txt'), index_lines.join("\n") + "\n")
  write_json(P[:combined], combined)
  File.write(P[:duplicates], (dup_lines.empty? ? ['No exact duplicates.'] : dup_lines).join("\n") + "\n")
  write_json(P[:nodes], nodes)
  File.write(P[:probe_report], (report + ["SELECTED: #{profile_name}", "UNIQUE: #{nodes.length}"]).join("\n") + "\n")
  File.write(P[:summary], "AUTO Xray subscription update\nSelected profile: #{profile_name}\nVLESS links: #{links.length}\nUnique technical nodes: #{nodes.length}\nRF: #{counts['RF']}\nEU: #{counts['EU']}\nWorld: #{counts['WORLD']}\nV2RayXS export: #{P[:combined]}\n")
  true
end

def xray_path
  resources = ENV['AUTO_XRAY_RESOURCES'].to_s
  x = File.join(resources, 'xray') unless resources.empty?
  return x if x && File.executable?(x)
  x = File.join(File.dirname(File.expand_path($PROGRAM_NAME)), 'xray')
  File.executable?(x) ? x : nil
end

def default_interface
  rc, out = run_cmd(['/sbin/route', '-n', 'get', 'default'], 5)
  return '' unless rc.zero?
  m = out.match(/^\s*interface:\s*(\S+)/)
  m ? m[1] : ''
end

def service_for_interface(iface)
  rc, out = run_cmd(['/usr/sbin/networksetup', '-listnetworkserviceorder'], 10)
  return '' unless rc.zero?
  current = nil
  out.each_line do |line|
    if (m = line.strip.match(/^\(\d+\)\s+(.+)$/))
      current = m[1].strip
      next
    end
    if current && (m = line.match(/Device:\s*([^)]+)\)/)) && m[1].strip == iface
      return current
    end
  end
  ''
end

def parse_proxy(text)
  p = { 'enabled' => false, 'server' => '', 'port' => 0 }
  text.each_line do |line|
    next unless line.include?(':')
    key, value = line.split(':', 2).map(&:strip)
    case key.downcase
    when 'enabled' then p['enabled'] = value.casecmp('yes').zero?
    when 'server' then p['server'] = value
    when 'port' then p['port'] = value.to_i
    end
  end
  p
end

def get_proxy_state(service)
  st = { 'service' => service }
  { 'web' => '-getwebproxy', 'secure' => '-getsecurewebproxy', 'socks' => '-getsocksfirewallproxy' }.each do |name, flag|
    rc, out = run_cmd(['/usr/sbin/networksetup', flag, service], 10)
    raise out unless rc.zero?
    st[name] = parse_proxy(out)
  end
  st
end

def set_proxy(service, kind, server, port, enabled)
  flags = {
    'web' => ['-setwebproxy', '-setwebproxystate'],
    'secure' => ['-setsecurewebproxy', '-setsecurewebproxystate'],
    'socks' => ['-setsocksfirewallproxy', '-setsocksfirewallproxystate']
  }
  set_flag, state_flag = flags.fetch(kind)
  unless server.to_s.empty? || port.to_i <= 0
    rc, out = run_cmd(['/usr/sbin/networksetup', set_flag, service, server, port.to_i.to_s], 10)
    raise out unless rc.zero?
  end
  rc, out = run_cmd(['/usr/sbin/networksetup', state_flag, service, enabled ? 'on' : 'off'], 10)
  raise out unless rc.zero?
end

def restore_proxy(st)
  %w[web secure socks].each do |kind|
    item = st[kind] || {}
    server = item['server'].to_s.empty? ? '127.0.0.1' : item['server'].to_s
    port = item['port'].to_i.zero? ? 1 : item['port'].to_i
    set_proxy(st['service'], kind, server, port, !!item['enabled']) rescue nil
  end
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

def our_process?(pid)
  cmd = process_command(pid)
  cmd.include?(P[:runtime_config]) || cmd.include?('AUTO Xray.app/Contents/Resources/xray')
end

def read_pid
  return 0 unless File.file?(P[:pid])
  pid = File.read(P[:pid]).to_i
  process_alive?(pid) && our_process?(pid) ? pid : 0
rescue StandardError
  0
end

def stop_core
  pid = read_pid
  if pid > 0
    Process.kill('TERM', pid) rescue nil
    24.times do
      break unless process_alive?(pid)
      sleep 0.25
    end
    Process.kill('KILL', pid) rescue nil if process_alive?(pid)
  end
  File.delete(P[:pid]) if File.exist?(P[:pid])
rescue StandardError
end

def load_nodes
  return [] unless File.file?(P[:nodes])
  JSON.parse(File.read(P[:nodes]))
rescue StandardError
  []
end

def read_mode
  if File.file?(P[:mode])
    m = JSON.parse(File.read(P[:mode])) rescue nil
    return m if m.is_a?(Hash) && !m['type'].to_s.empty?
  end
  { 'type' => 'auto', 'group' => 'RF' }
end

def write_mode(mode)
  write_json(P[:mode], mode)
end

def build_config(mode)
  nodes = load_nodes
  raise 'No nodes. Update subscription first.' if nodes.empty?
  selected = []
  cfg = {
    'log' => { 'loglevel' => 'warning' },
    'inbounds' => [
      { 'listen' => '127.0.0.1', 'port' => SOCKS_PORT, 'protocol' => 'socks', 'settings' => { 'auth' => 'noauth', 'udp' => false }, 'tag' => 'socks' },
      { 'listen' => '127.0.0.1', 'port' => HTTP_PORT, 'protocol' => 'http', 'settings' => {}, 'tag' => 'http' }
    ]
  }
  if mode['type'] == 'manual'
    node = nodes.find { |n| n['id'] == mode['node'] }
    raise 'Selected manual node no longer exists' unless node
    selected = [node]
    cfg['routing'] = { 'domainStrategy' => 'AsIs', 'rules' => [{ 'type' => 'field', 'port' => '0-65535', 'outboundTag' => node['tag'] }] }
  else
    group = mode['group'].to_s.empty? ? 'RF' : mode['group'].to_s
    selected = nodes.select { |n| n['group'] == group }
    raise "No nodes in group #{group}" if selected.empty?
    prefix = "ax-#{group.downcase}-"
    cfg['observatory'] = { 'subjectSelector' => [prefix], 'probeURL' => PROBE_URL, 'probeInterval' => '15s' }
    cfg['routing'] = {
      'domainStrategy' => 'AsIs',
      'balancers' => [{ 'tag' => 'auto-balance', 'selector' => [prefix], 'strategy' => { 'type' => 'leastPing' } }],
      'rules' => [{ 'type' => 'field', 'port' => '0-65535', 'balancerTag' => 'auto-balance' }]
    }
  end
  cfg['outbounds'] = selected.map { |n| n['outbound'] } + [
    { 'tag' => 'direct', 'protocol' => 'freedom', 'settings' => {} },
    { 'tag' => 'block', 'protocol' => 'blackhole', 'settings' => {} }
  ]
  write_json(P[:runtime_config], cfg)
end

def validate_config
  xray = xray_path
  raise 'Xray core not found' unless xray
  [['run', '-test', '-config', P[:runtime_config]], ['-test', '-config', P[:runtime_config]]].each do |args|
    rc, = run_cmd([xray] + args, 15)
    return true if rc.zero?
  end
  raise 'Config validation failed'
end

def probe
  run_cmd(['/usr/bin/curl', '--silent', '--show-error', '--max-time', '15', '--socks5-hostname', "127.0.0.1:#{SOCKS_PORT}", '-o', '/dev/null', '-w', '%{http_code} %{time_total}', PROBE_URL], 20)
end

def start_core(mode)
  build_config(mode)
  validate_config
  xray = xray_path
  FileUtils.mkdir_p(File.dirname(P[:runtime_log]))
  log = File.open(P[:runtime_log], 'a')
  log.puts("\n\n=== START #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} ===")
  log.flush
  pid = Process.spawn(xray, 'run', '-config', P[:runtime_config], out: log, err: log, pgroup: true)
  sleep 2
  unless process_alive?(pid)
    log.close
    raise 'Xray stopped immediately'
  end
  rc, out = probe
  unless rc.zero? && out.strip.start_with?('204 ')
    Process.kill('TERM', pid) rescue nil
    log.close
    raise "Proxy probe failed: #{out.strip}"
  end
  File.write(P[:pid], pid.to_s)
  File.chmod(0o600, P[:pid]) rescue nil
  log.close
  pid
end

def system_proxy_on
  iface = default_interface
  svc = service_for_interface(iface)
  return [false, iface, svc] if svc.empty?
  st = get_proxy_state(svc) rescue nil
  return [false, iface, svc] unless st
  ok = st['web']['enabled'] && st['web']['server'] == '127.0.0.1' && st['web']['port'] == HTTP_PORT &&
       st['secure']['enabled'] && st['secure']['server'] == '127.0.0.1' && st['secure']['port'] == HTTP_PORT &&
       st['socks']['enabled'] && st['socks']['server'] == '127.0.0.1' && st['socks']['port'] == SOCKS_PORT
  [ok, iface, svc]
end

def current_status
  pid = read_pid
  running = pid > 0 && process_alive?(pid)
  proxy, iface, svc = system_proxy_on
  { 'on' => running && proxy, 'running' => running, 'proxy' => proxy, 'pid' => pid, 'interface' => iface, 'service' => svc, 'mode' => read_mode, 'nodes' => load_nodes.length }
end

def ensure_proxy
  pid = read_pid
  return false unless pid > 0 && process_alive?(pid)
  iface = default_interface
  svc = service_for_interface(iface)
  return false if svc.empty?
  ok, = system_proxy_on
  return true if ok
  set_proxy(svc, 'web', '127.0.0.1', HTTP_PORT, true)
  set_proxy(svc, 'secure', '127.0.0.1', HTTP_PORT, true)
  set_proxy(svc, 'socks', '127.0.0.1', SOCKS_PORT, true)
  true
end

def start_proxy(mode = nil)
  st = current_status
  return if st['on']
  if st['running']
    ensure_proxy
    write_status
    return
  end
  if st['proxy'] && !st['running'] && File.file?(P[:proxy_state])
    old = JSON.parse(File.read(P[:proxy_state])) rescue nil
    restore_proxy(old) if old
    File.delete(P[:proxy_state]) rescue nil
  end
  iface = default_interface
  svc = service_for_interface(iface)
  raise 'Active network service not found' if svc.empty?
  prior = get_proxy_state(svc)
  write_json(P[:proxy_state], prior)
  mode ||= read_mode
  begin
    start_core(mode)
    set_proxy(svc, 'web', '127.0.0.1', HTTP_PORT, true)
    set_proxy(svc, 'secure', '127.0.0.1', HTTP_PORT, true)
    set_proxy(svc, 'socks', '127.0.0.1', SOCKS_PORT, true)
    write_mode(mode)
    write_status
  rescue StandardError
    stop_core
    restore_proxy(prior)
    raise
  end
end

def stop_proxy
  stop_core
  if File.file?(P[:proxy_state])
    old = JSON.parse(File.read(P[:proxy_state])) rescue nil
    restore_proxy(old) if old
    File.delete(P[:proxy_state]) rescue nil
  end
  write_status
end

def switch_mode(mode)
  st = current_status
  old = read_mode
  unless st['on']
    write_mode(mode)
    write_status
    return
  end
  stop_core
  begin
    start_core(mode)
    write_mode(mode)
    write_status
  rescue StandardError
    begin
      start_core(old)
      write_mode(old)
      write_status
    rescue StandardError
      stop_proxy
    end
    raise 'Could not switch mode'
  end
end

def mode_label(mode)
  if mode['type'] == 'manual'
    n = load_nodes.find { |x| x['id'] == mode['node'] }
    "Manual · #{n ? n['name'] : mode['node']}"
  else
    "Auto · #{mode['group'].to_s.empty? ? 'RF' : mode['group']}"
  end
end

def write_status
  st = current_status
  text = "AUTO Xray STATUS\nSTATE: #{st['on'] ? 'ON' : 'OFF'}\nMODE: #{mode_label(st['mode'])}\nNODES: #{st['nodes']}\nPID: #{st['pid']}\nInterface: #{st['interface']}\nNetwork service: #{st['service']}\n"
  File.write(P[:status], text)
end


def xml_escape(s)
  s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;').gsub("'", '&apos;')
end

def app_bundle_path
  resources = ENV['AUTO_XRAY_RESOURCES'].to_s
  return '' if resources.empty?
  File.expand_path('../..', resources)
end

def migrate_legacy_data
  new_sub = P[:sub_url]
  new_hwid = P[:hwid]

  unless File.file?(new_sub) && !File.read(new_sub).strip.empty?
    [
      File.join(Dir.home, 'Library', 'Application Support', 'AUTO-Xray', 'subscription_url.txt'),
      File.join(Dir.home, 'Library', 'Application Support', 'VLESS-Tools', 'subscription_url.txt')
    ].each do |old|
      next unless File.file?(old) && !File.read(old).strip.empty?
      FileUtils.cp(old, new_sub)
      File.chmod(0o600, new_sub) rescue nil
      break
    end
  end

  unless File.file?(new_hwid) && !File.read(new_hwid).strip.empty?
    [
      File.join(Dir.home, 'Library', 'Application Support', 'AUTO-Xray', 'hwid.txt'),
      File.join(Dir.home, 'Library', 'Application Support', 'VLESS-Tools', 'hwid.txt')
    ].each do |old|
      next unless File.file?(old) && !File.read(old).strip.empty?
      FileUtils.cp(old, new_hwid)
      File.chmod(0o600, new_hwid) rescue nil
      break
    end
  end

  old_work = File.join(Dir.home, 'Desktop', 'vless-work')
  if Dir.exist?(old_work) &&
     (File.file?(File.join(old_work, 'nodes.json')) ||
      File.file?(File.join(old_work, 'V2RayXS_IMPORT_ALL.json')))
    FileUtils.cp(File.join(old_work, 'nodes.json'), P[:nodes]) rescue nil
    FileUtils.cp(File.join(old_work, 'vless-links.txt'), P[:vless_links]) rescue nil
    FileUtils.cp(File.join(old_work, 'DUPLICATES.txt'), P[:duplicates]) rescue nil
    FileUtils.cp(File.join(old_work, 'SUMMARY.txt'), P[:summary]) rescue nil
    if Dir.exist?(File.join(old_work, 'json-all'))
      FileUtils.rm_rf(P[:json_all])
      FileUtils.cp_r(File.join(old_work, 'json-all'), P[:json_all])
    end
    if Dir.exist?(File.join(old_work, 'json-unique'))
      FileUtils.rm_rf(P[:json_unique])
      FileUtils.cp_r(File.join(old_work, 'json-unique'), P[:json_unique])
    end
    FileUtils.mkdir_p(P[:exports])
    FileUtils.cp(File.join(old_work, 'V2RayXS_IMPORT_ALL.json'), P[:combined]) rescue nil

    legacy = File.join(P[:support], 'Legacy')
    FileUtils.mkdir_p(legacy)
    stamp = Time.now.strftime('%Y%m%d-%H%M%S')
    target = File.join(legacy, "vless-work-from-Desktop-#{stamp}")
    FileUtils.mv(old_work, target) rescue nil
  end
end

def install_login_agent
  app = app_bundle_path
  return false if app.empty? || !Dir.exist?(app)

  launch_dir = File.join(Dir.home, 'Library', 'LaunchAgents')
  FileUtils.mkdir_p(launch_dir)
  plist = File.join(launch_dir, 'local.autoxray.menubar.plist')

  content = <<~PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>local.autoxray.menubar</string>
      <key>ProgramArguments</key>
      <array>
        <string>/usr/bin/open</string>
        <string>#{xml_escape(app)}</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
    </dict>
    </plist>
  PLIST

  File.write(plist, content)
  run_cmd(['/bin/launchctl', 'unload', plist], 5)
  run_cmd(['/bin/launchctl', 'load', plist], 5)
  true
end

def uninstall_login_agent
  plist = File.join(Dir.home, 'Library', 'LaunchAgents', 'local.autoxray.menubar.plist')
  run_cmd(['/bin/launchctl', 'unload', plist], 5) if File.file?(plist)
  File.delete(plist) rescue nil
  true
end

def bootstrap
  ensure_dirs
  migrate_legacy_data
  install_login_agent
  write_status
  true
end

def main
  cmd = ARGV.shift.to_s
  case cmd
  when 'bootstrap'
    bootstrap
    puts 'OK'
  when 'install-login-agent'
    puts(install_login_agent ? 'OK' : 'FAILED')
  when 'uninstall-login-agent'
    puts(uninstall_login_agent ? 'OK' : 'FAILED')
  when 'menu-state'
    st = current_status
    has_url = File.file?(P[:sub_url]) && !File.read(P[:sub_url]).strip.empty?
    puts JSON.generate({ 'on' => st['on'], 'mode' => st['mode'], 'modeLabel' => mode_label(st['mode']), 'nodes' => st['nodes'], 'hasURL' => has_url, 'dataPath' => P[:data] })
  when 'menu-nodes'
    load_nodes.each { |n| puts [n['group'], n['id'], n['name'], "#{n['address']}:#{n['port']}"] .join("\t") }
  when 'get-url'
    print File.read(P[:sub_url]).strip if File.file?(P[:sub_url])
  when 'update'
    url = nil
    if ARGV[0] == '--url'
      ARGV.shift
      url = ARGV.shift.to_s
    end
    was = current_status['on']
    mode = read_mode
    update_subscription(url)
    if was
      begin
        switch_mode(mode)
      rescue StandardError
        switch_mode({ 'type' => 'auto', 'group' => 'RF' })
      end
    end
    write_status
  when 'start'
    start_proxy
    puts 'ON'
  when 'stop'
    stop_proxy
    puts 'OFF'
  when 'ensure-proxy'
    puts(ensure_proxy ? 'OK' : 'IDLE')
    write_status
  when 'mode'
    type = ARGV.shift.to_s
    value = ARGV.shift.to_s
    raise 'mode requires arguments' if type.empty? || value.empty?
    if type == 'auto'
      switch_mode({ 'type' => 'auto', 'group' => value })
    elsif type == 'manual'
      switch_mode({ 'type' => 'manual', 'node' => value })
    else
      raise 'unknown mode'
    end
  when 'paths'
    puts JSON.generate({ 'support' => P[:support], 'data' => P[:data], 'jsonUnique' => P[:json_unique], 'exports' => P[:exports], 'logs' => P[:logs], 'status' => P[:status] })
  else
    raise 'unknown command'
  end
rescue StandardError => e
  warn "ERROR: #{e.message}"
  write_status rescue nil
  exit 50
end

main

use framework "AppKit"
use framework "Foundation"
use scripting additions

property NSStatusBar : a reference to current application's NSStatusBar
property NSVariableStatusItemLength : current application's NSVariableStatusItemLength
property NSMenu : a reference to current application's NSMenu
property NSMenuItem : a reference to current application's NSMenuItem
property NSFont : a reference to current application's NSFont
property NSApp : a reference to current application's NSApp
property NSString : a reference to current application's NSString
property NSJSONSerialization : a reference to current application's NSJSONSerialization

property statusItem : missing value
property statusMenu : missing value
property stateItem : missing value
property toggleItem : missing value
property autoRFItem : missing value
property autoEUItem : missing value
property autoWorldItem : missing value
property manualItem : missing value
property updateItem : missing value
property lastStateOn : false
property currentModeType : ""
property currentModeValue : ""

on run
	current application's NSApplication's sharedApplication()
	
	set bundlePath to POSIX path of (path to me)
	if bundlePath starts with "/Volumes/" then
		display dialog "Сначала перетащите AUTO Xray в папку Applications, затем запустите программу оттуда." buttons {"OK"} default button "OK" with title "AUTO Xray"
		NSApp's terminate:me
		return
	end if
	
	try
		my runHelper("bootstrap")
	on error errText
		display dialog "Не удалось выполнить первичную настройку AUTO Xray." & return & return & errText buttons {"OK"} default button "OK" with icon stop
	end try
	
	my setupMenu()
	my refreshAll()
end run

on idle
	-- Health checks can run networksetup/curl for several seconds on Catalina.
	-- Run them outside the AppleScript UI thread so the menu never freezes.
	try
		my runHelperAsync("ensure-proxy")
	end try
	return 15
end idle

on resourcesPath()
	return (current application's NSBundle's mainBundle()'s resourcePath() as text)
end resourcesPath

on helperPath()
	return my resourcesPath() & "/auto-xray-helper.rb"
end helperPath

on shellQuoted(t)
	return quoted form of (t as text)
end shellQuoted

on runHelper(argsText)
	set cmd to "/usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES=" & my shellQuoted(my resourcesPath()) & " /usr/bin/ruby -EUTF-8:UTF-8 " & my shellQuoted(my helperPath()) & " " & argsText
	return do shell script cmd
end runHelper

on runHelperAsync(argsText)
	set cmd to "/usr/bin/env LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 AUTO_XRAY_RESOURCES=" & my shellQuoted(my resourcesPath()) & " /usr/bin/ruby -EUTF-8:UTF-8 " & my shellQuoted(my helperPath()) & " " & argsText & " </dev/null >/dev/null 2>&1 &"
	do shell script cmd
end runHelperAsync

on parseJSONText(t)
	set dataObj to (NSString's stringWithString:t)'s dataUsingEncoding:(current application's NSUTF8StringEncoding)
	set {obj, err} to NSJSONSerialization's JSONObjectWithData:dataObj options:0 |error|:(reference)
	if obj is missing value then return missing value
	return obj
end parseJSONText

on supportDataPath()
	return (POSIX path of (path to home folder)) & "Library/Application Support/AUTO Xray/Data"
end supportDataPath

on logsPath()
	return (POSIX path of (path to home folder)) & "Library/Logs/AUTO Xray"
end logsPath

on setupMenu()
	set statusItem to NSStatusBar's systemStatusBar()'s statusItemWithLength:NSVariableStatusItemLength
	statusItem's button()'s setTitle:"🕊"
	statusItem's button()'s setFont:(NSFont's fontWithName:"Apple Color Emoji" |size|:15)
	statusItem's button()'s setAlphaValue:0.28
	
	set statusMenu to NSMenu's alloc()'s initWithTitle:"AUTO Xray"
	
	set stateItem to NSMenuItem's alloc()'s initWithTitle:"AUTO Xray 2.5.2: проверка..." action:(missing value) keyEquivalent:""
	stateItem's setEnabled:false
	statusMenu's addItem:stateItem
	
	set toggleItem to NSMenuItem's alloc()'s initWithTitle:"Включить" action:"toggleProxy:" keyEquivalent:""
	toggleItem's setTarget:me
	statusMenu's addItem:toggleItem
	
	statusMenu's addItem:(NSMenuItem's separatorItem())
	
	set autoRFItem to NSMenuItem's alloc()'s initWithTitle:"Автовыбор · RF" action:"autoRF:" keyEquivalent:""
	autoRFItem's setTarget:me
	statusMenu's addItem:autoRFItem
	
	set autoEUItem to NSMenuItem's alloc()'s initWithTitle:"Автовыбор · EU" action:"autoEU:" keyEquivalent:""
	autoEUItem's setTarget:me
	statusMenu's addItem:autoEUItem
	
	set autoWorldItem to NSMenuItem's alloc()'s initWithTitle:"Автовыбор · World" action:"autoWorld:" keyEquivalent:""
	autoWorldItem's setTarget:me
	statusMenu's addItem:autoWorldItem
	
	set manualItem to NSMenuItem's alloc()'s initWithTitle:"Ручной выбор" action:(missing value) keyEquivalent:""
	statusMenu's addItem:manualItem
	
	statusMenu's addItem:(NSMenuItem's separatorItem())
	
	set updateItem to NSMenuItem's alloc()'s initWithTitle:"Обновить подписку" action:"updateSubscription:" keyEquivalent:""
	updateItem's setTarget:me
	statusMenu's addItem:updateItem
	
	set dataItem to NSMenuItem's alloc()'s initWithTitle:"Открыть данные" action:"openData:" keyEquivalent:""
	dataItem's setTarget:me
	statusMenu's addItem:dataItem
	
	set exportItem to NSMenuItem's alloc()'s initWithTitle:"Открыть экспорт V2RayXS" action:"openExport:" keyEquivalent:""
	exportItem's setTarget:me
	statusMenu's addItem:exportItem
	
	set logItem to NSMenuItem's alloc()'s initWithTitle:"Открыть лог" action:"openLog:" keyEquivalent:""
	logItem's setTarget:me
	statusMenu's addItem:logItem
	
	set versionItem to NSMenuItem's alloc()'s initWithTitle:"Версия 2.5.2 · Catalina Intel" action:(missing value) keyEquivalent:""
	versionItem's setEnabled:false
	statusMenu's addItem:versionItem
	
	statusMenu's addItem:(NSMenuItem's separatorItem())
	
	set quitItem to NSMenuItem's alloc()'s initWithTitle:"Выход" action:"quitApp:" keyEquivalent:"q"
	quitItem's setTarget:me
	statusMenu's addItem:quitItem
	
	statusItem's setMenu:statusMenu
end setupMenu

on setDoveState(onState)
	if onState then
		statusItem's button()'s setAlphaValue:1.0
	else
		statusItem's button()'s setAlphaValue:0.28
	end if
end setDoveState

on setCheck(itemObj, checked)
	if checked then
		itemObj's setState:1
	else
		itemObj's setState:0
	end if
end setCheck

on refreshAll()
	set stateText to my runHelper("menu-state")
	set obj to my parseJSONText(stateText)
	if obj is missing value then return
	
	set lastStateOn to (obj's objectForKey:"on") as boolean
	set modeLabel to (obj's objectForKey:"modeLabel") as text
	set nodesCount to (obj's objectForKey:"nodes") as integer
	set modeObj to obj's objectForKey:"mode"
	
	set currentModeType to (modeObj's objectForKey:"type") as text
	if currentModeType is "auto" then
		set currentModeValue to (modeObj's objectForKey:"group") as text
	else
		set currentModeValue to (modeObj's objectForKey:"node") as text
	end if
	
	my setDoveState(lastStateOn)
	
	if lastStateOn then
		stateItem's setTitle:"AUTO Xray 2.5.2: ON · " & modeLabel
		toggleItem's setTitle:"Выключить"
	else
		stateItem's setTitle:"AUTO Xray 2.5.2: OFF · " & modeLabel
		toggleItem's setTitle:"Включить"
	end if
	
	my setCheck(autoRFItem, currentModeType is "auto" and currentModeValue is "RF")
	my setCheck(autoEUItem, currentModeType is "auto" and currentModeValue is "EU")
	my setCheck(autoWorldItem, currentModeType is "auto" and currentModeValue is "WORLD")
	
	updateItem's setTitle:"Обновить подписку (" & nodesCount & " узлов)"
	my rebuildManualMenu()
end refreshAll

on rebuildManualMenu()
	set topMenu to NSMenu's alloc()'s initWithTitle:"Ручной выбор"
	
	repeat with groupName in {"RF", "EU", "WORLD"}
		set groupMenu to NSMenu's alloc()'s initWithTitle:(groupName as text)
		set groupItem to NSMenuItem's alloc()'s initWithTitle:(groupName as text) action:(missing value) keyEquivalent:""
		groupItem's setSubmenu:groupMenu
		topMenu's addItem:groupItem
	end repeat
	
	set nodeText to ""
	try
		set nodeText to my runHelper("menu-nodes")
	end try
	
	repeat with ln in paragraphs of nodeText
		if (ln as text) is not "" then
			set AppleScript's text item delimiters to tab
			set parts to text items of (ln as text)
			set AppleScript's text item delimiters to ""
			
			if (count of parts) ≥ 4 then
				set grp to item 1 of parts
				set nodeID to item 2 of parts
				set nodeName to item 3 of parts
				set ep to item 4 of parts
				
				set titleText to nodeName & " · " & ep
				set mi to NSMenuItem's alloc()'s initWithTitle:titleText action:"manualNode:" keyEquivalent:""
				mi's setTarget:me
				mi's setRepresentedObject:nodeID
				
				if currentModeType is "manual" and currentModeValue is nodeID then mi's setState:1
				
				if grp is "RF" then
					set groupIndex to 0
				else if grp is "EU" then
					set groupIndex to 1
				else
					set groupIndex to 2
				end if
				
				set gi to topMenu's itemAtIndex:groupIndex
				(gi's submenu())'s addItem:mi
			end if
		end if
	end repeat
	
	manualItem's setSubmenu:topMenu
end rebuildManualMenu

on toggleProxy_(sender)
	try
		if lastStateOn then
			my runHelper("stop")
		else
			my runHelper("start")
		end if
	on error errText
		display dialog "Не удалось переключить AUTO Xray." & return & return & errText buttons {"OK"} default button "OK" with icon stop
	end try
	my refreshAll()
end toggleProxy_

on autoRF_(sender)
	my chooseAuto("RF")
end autoRF_

on autoEU_(sender)
	my chooseAuto("EU")
end autoEU_

on autoWorld_(sender)
	my chooseAuto("WORLD")
end autoWorld_

on chooseAuto(grp)
	try
		my runHelper("mode auto " & grp)
	on error errText
		display dialog "Не удалось переключить режим." & return & return & errText buttons {"OK"} default button "OK" with icon stop
	end try
	my refreshAll()
end chooseAuto

on manualNode_(sender)
	set nodeID to sender's representedObject() as text
	try
		my runHelper("mode manual " & my shellQuoted(nodeID))
	on error errText
		display dialog "Не удалось включить выбранный узел." & return & return & errText buttons {"OK"} default button "OK" with icon stop
	end try
	my refreshAll()
end manualNode_

on updateSubscription_(sender)
	set existingURL to ""
	try
		set existingURL to my runHelper("get-url")
	end try
	
	set r to display dialog "HTTPS-ссылка подписки:" default answer existingURL buttons {"Отмена", "Обновить"} default button "Обновить" with title "AUTO Xray"
	if button returned of r is not "Обновить" then return
	set newURL to text returned of r
	if newURL is "" then return
	
	updateItem's setTitle:"Обновление..."
	try
		my runHelper("update --url " & my shellQuoted(newURL))
	on error errText
		display dialog "Не удалось обновить подписку." & return & return & errText buttons {"OK"} default button "OK" with icon stop
	end try
	my refreshAll()
end updateSubscription_

on openData_(sender)
	do shell script "/usr/bin/open " & quoted form of (my supportDataPath())
end openData_

on openExport_(sender)
	do shell script "/usr/bin/open -R " & quoted form of ((my supportDataPath()) & "/exports/V2RayXS_IMPORT_ALL.json")
end openExport_

on openLog_(sender)
	set p to (my logsPath()) & "/runtime.log"
	try
		do shell script "/usr/bin/open " & quoted form of p
	on error
		display dialog "Лог пока не создан." buttons {"OK"} default button "OK"
	end try
end openLog_

on quitApp_(sender)
	try
		NSStatusBar's systemStatusBar()'s removeStatusItem:statusItem
	end try
	NSApp's terminate:me
end quitApp_

on quit
	try
		NSStatusBar's systemStatusBar()'s removeStatusItem:statusItem
	end try
	continue quit
end quit

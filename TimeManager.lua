
-- speed optimizations (mostly so update functions are faster)
local _G = getfenv(0)
local date = _G.date
local abs = _G.abs
local min = _G.min
local max = _G.max
local floor = _G.floor
local format = _G.format
local mod = _G.mod
local tonumber = _G.tonumber
local gsub = _G.gsub
local GetGameTime = _G.GetGameTime

-- private data
local SEC_TO_MINUTE_FACTOR = 1 / 60
local SEC_TO_HOUR_FACTOR = SEC_TO_MINUTE_FACTOR * SEC_TO_MINUTE_FACTOR
MAX_TIMER_SEC = 99 * 3600 + 59 * 60 + 59 -- 99:59:59

local WARNING_SOUND_TRIGGER_OFFSET = -2 * SEC_TO_MINUTE_FACTOR -- play warning sound 2 sec before alarm sound

local Settings = {
	militaryTime = false,
	localTime = false,

	alarmHour = 12,
	alarmMinute = 00,
	alarmAM = true,
	alarmMessage = "",
	alarmEnabled = false
}

local UIDropDownMenu_ButtonInfo = {}

function UIDropDownMenu_CreateInfo()
	-- Reuse the same table to prevent memory churn
	local info = UIDropDownMenu_ButtonInfo
	for k, v in pairs(info) do
		info[k] = nil
	end
	return UIDropDownMenu_ButtonInfo
end

function UIDropDownMenu_SetWidth(width, frame, padding)
	if not frame then frame = this end
	_G[frame:GetName() .. "Middle"]:SetWidth(width)
	local defaultPadding = 25
	if padding then
		frame:SetWidth(width + padding)
		_G[frame:GetName() .. "Text"]:SetWidth(width)
	else
		frame:SetWidth(width + defaultPadding + defaultPadding)
		_G[frame:GetName() .. "Text"]:SetWidth(width - defaultPadding)
	end
	frame.noResize = 1
end

local origToggleGameMenu = ToggleGameMenu
function ToggleGameMenu(clicked)
	if TimeManagerFrame:IsShown() and not IsOptionFrameOpen() then
		TimeManagerCloseButton:Click()
	else
		origToggleGameMenu(clicked)
	end
end

local origWorldFrame_OnUpdate = WorldFrame_OnUpdate
function WorldFrame_OnUpdate(elapsed)
	if not elapsed then elapsed = arg1 end
	origWorldFrame_OnUpdate(elapsed)
	-- Process time manager alarm onUpdates in order to allow the alarm to go off without the clock
	-- being visible
	if TimeManagerClockButton and not TimeManagerClockButton:IsVisible() and TimeManager_ShouldCheckAlarm() then
		TimeManager_CheckAlarm(elapsed)
	end
	if StopwatchTicker and not StopwatchTicker:IsVisible() and Stopwatch_IsPlaying() then
		StopwatchTicker_OnUpdate(elapsed)
	end
end

local function _TimeManager_ComputeMinutes(hour, minute, militaryTime, am)
	local minutes
	if militaryTime then
		minutes = minute + hour * 60
	else
		local h = hour
		if am then
			if h == 12 then
				h = 0
			end
		else
			if h ~= 12 then
				h = h + 12
			end
		end
		minutes = minute + h * 60
	end
	return minutes
end

local function _TimeManager_GetCurrentMinutes(localTime)
	local currTime
	if localTime then
		local dateInfo = date("*t")
		local hour, minute = dateInfo.hour, dateInfo.min
		currTime = minute + hour * 60
	else
		local hour, minute = GetGameTime()
		currTime = minute + hour * 60
	end
	return currTime
end

function GameTime_GetFormattedTime(hour, minute, wantAMPM)
	if TimeManagerOptions and TimeManagerOptions.militaryTime == 1 then
		return format(TIMEMANAGER_TICKER_24HOUR, hour, minute)
	else
		if wantAMPM then
			local timeFormat = TIME_TWELVEHOURAM
			if hour == 0 then
				hour = 12
			elseif hour == 12 then
				timeFormat = TIME_TWELVEHOURPM
			elseif hour > 12 then
				timeFormat = TIME_TWELVEHOURPM
				hour = hour - 12
			end
			return format(timeFormat, hour, minute)
		else
			if hour == 0 then
				hour = 12
			elseif hour > 12 then
				hour = hour - 12
			end
			return format(TIMEMANAGER_TICKER_12HOUR, hour, minute)
		end
	end
end

function GameTime_GetLocalTime(wantAMPM)
	local dateInfo = date("*t")
	local hour, minute = dateInfo.hour, dateInfo.min
	return GameTime_GetFormattedTime(hour, minute, wantAMPM), hour, minute
end

function GameTime_GetGameTime(wantAMPM)
	local hour, minute = GetGameTime()
	return GameTime_GetFormattedTime(hour, minute, wantAMPM), hour, minute
end

function GameTime_GetTime(showAMPM)
	if TimeManagerOptions and TimeManagerOptions.localTime == 1 then
		return GameTime_GetLocalTime(showAMPM)
	else
		return GameTime_GetGameTime(showAMPM)
	end
end

function GameTime_UpdateTooltip()
	-- title
	GameTooltip:AddLine(TIMEMANAGER_TOOLTIP_TITLE, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
	-- realm time
	GameTooltip:AddDoubleLine(
		TIMEMANAGER_TOOLTIP_REALMTIME,
		GameTime_GetGameTime(true),
		NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
		HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
	-- local time
	GameTooltip:AddDoubleLine(
		TIMEMANAGER_TOOLTIP_LOCALTIME,
		GameTime_GetLocalTime(true),
		NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
		HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
end

function GameTimeFrame_Update()
	local hour, minute = GetGameTime()
	local time = (hour * 60) + minute
	if time ~= this.timeOfDay then
		this.timeOfDay = time
		local minx = 0
		local maxx = 50 / 128
		local miny = 0
		local maxy = 50 / 64
		if time < GAMETIME_DAWN or time >= GAMETIME_DUSK then
			minx = minx + 0.5
			maxx = maxx + 0.5
		end
		GameTimeTexture:SetTexCoord(minx, maxx, miny, maxy)
	end
	if GameTooltip:IsOwned(this) then
		GameTooltip:ClearLines()
		if not TimeManagerClockButton or not TimeManagerClockButton:IsVisible() or TimeManager_IsAlarmFiring() then
			GameTime_UpdateTooltip()
			GameTooltip:AddLine(" ")
		end
		GameTooltip:AddLine(TIMEMANAGER_TOOLTIP_TOGGLE_CLOCK_SETTINGS)
		GameTooltip:Show()
	end
end

function GameTimeFrame_OnClick()
	TimeManager_Toggle()
end

local function _TimeManager_Setting_SetBool(option, value)
	if value then
		TimeManagerOptions[option] = 1
	else
		TimeManagerOptions[option] = 0
	end
	Settings[option] = value
end

local function _TimeManager_Setting_Set(option, value)
	TimeManagerOptions[option] = value
	Settings[option] = value
end

local function _TimeManager_Setting_SetTime()
	local alarmTime = _TimeManager_ComputeMinutes(Settings.alarmHour, Settings.alarmMinute, Settings.militaryTime, Settings.alarmAM)
	TimeManagerOptions.alarmTime = alarmTime
end

-- TimeManagerFrame

function TimeManager_Toggle()
	if TimeManagerFrame:IsShown() then
		TimeManagerFrame:Hide()
	else
		TimeManagerFrame:Show()
	end
end

function TimeManagerFrame_OnLoad()
	if not TimeManagerOptions then
		TimeManagerOptions = {}
	end

	Settings.militaryTime = TimeManagerOptions.militaryTime == 1
	Settings.localTime = TimeManagerOptions.localTime == 1
	local alarmTime = tonumber(TimeManagerOptions.alarmTime)
	if not alarmTime then alarmTime = 0 end
	Settings.alarmHour = floor(alarmTime / 60)
	Settings.alarmMinute = max(min(alarmTime - Settings.alarmHour * 60, 59), 0)
	Settings.alarmHour = max(min(Settings.alarmHour, 23), 0)
	if not Settings.militaryTime then
		if Settings.alarmHour == 0 then
			Settings.alarmHour = 12
			Settings.alarmAM = true
		elseif Settings.alarmHour < 12 then
			Settings.alarmAM = true
		elseif Settings.alarmHour == 12 then
			Settings.alarmAM = false
		else
			Settings.alarmHour = Settings.alarmHour - 12
			Settings.alarmAM = false
		end
	end
	Settings.alarmMessage = TimeManagerOptions.alarmMessage
	Settings.alarmEnabled = TimeManagerOptions.alarmEnabled == 1

	UIDropDownMenu_Initialize(TimeManagerAlarmHourDropDown, TimeManagerAlarmHourDropDown_Initialize)
	UIDropDownMenu_SetWidth(30, TimeManagerAlarmHourDropDown, 40)

	UIDropDownMenu_Initialize(TimeManagerAlarmMinuteDropDown, TimeManagerAlarmMinuteDropDown_Initialize)
	UIDropDownMenu_SetWidth(30, TimeManagerAlarmMinuteDropDown, 40)

	UIDropDownMenu_Initialize(TimeManagerAlarmAMPMDropDown, TimeManagerAlarmAMPMDropDown_Initialize)
	-- some languages have ridonculously long am/pm strings (i'm looking at you French) so we may have to
	-- readjust the ampm dropdown width plus do some reanchoring if the text is too wide
	local maxAMPMWidth
	TimeManagerAMPMDummyText:SetText(TIMEMANAGER_AM)
	maxAMPMWidth = TimeManagerAMPMDummyText:GetWidth()
	TimeManagerAMPMDummyText:SetText(TIMEMANAGER_PM)
	if maxAMPMWidth < TimeManagerAMPMDummyText:GetWidth() then
		maxAMPMWidth = TimeManagerAMPMDummyText:GetWidth()
	end
	maxAMPMWidth = ceil(maxAMPMWidth)
	if maxAMPMWidth > 40 then
		UIDropDownMenu_SetWidth(maxAMPMWidth + 20, TimeManagerAlarmAMPMDropDown, 40)
		TimeManagerAlarmAMPMDropDown:SetScript("OnShow", TimeManagerAlarmAMPMDropDown_OnShow)
		TimeManagerAlarmAMPMDropDown:SetScript("OnHide", TimeManagerAlarmAMPMDropDown_OnHide)
	else
		UIDropDownMenu_SetWidth(40, TimeManagerAlarmAMPMDropDown, 40)
	end

	TimeManager_Update()
end

function TimeManagerFrame_OnUpdate()
	TimeManager_UpdateTimeTicker()
end

function TimeManagerFrame_OnShow()
	TimeManager_Update()
	TimeManagerStopwatchCheck:SetChecked(StopwatchFrame:IsShown())
	PlaySound("igCharacterInfoOpen")
end

function TimeManagerFrame_OnHide()
	PlaySound("igCharacterInfoClose")
end

function TimeManagerCloseButton_OnClick()
	TimeManagerFrame:Hide()
end

function TimeManagerStopwatchCheck_OnClick()
	Stopwatch_Toggle()
	if this:GetChecked() then
		PlaySound("igMainMenuOptionCheckBoxOn")
	else
		PlaySound("igMainMenuQuit")
	end
end

function TimeManagerAlarmHourDropDown_Initialize()
	local info = UIDropDownMenu_CreateInfo()

	local alarmHour = Settings.alarmHour
	local militaryTime = Settings.militaryTime

	local hourMin, hourMax
	if militaryTime then
		hourMin = 0
		hourMax = 23
	else
		hourMin = 1
		hourMax = 12
	end
	for hour = hourMin, hourMax, 1 do
		info.value = hour
		if militaryTime then
			info.text = format(TIMEMANAGER_24HOUR, hour)
		else
			info.text = hour
			info.justifyH = "RIGHT"
		end
		info.func = TimeManagerAlarmHourDropDown_OnClick
		if hour == alarmHour then
			info.checked = 1
			UIDropDownMenu_SetText(info.text, TimeManagerAlarmHourDropDown)
		else
			info.checked = nil
		end
		UIDropDownMenu_AddButton(info)
	end
end

function TimeManagerAlarmMinuteDropDown_Initialize()
	local info = UIDropDownMenu_CreateInfo()
	local alarmMinute = Settings.alarmMinute
	for minute = 0, 55, 5 do
		info.value = minute
		info.text = format(TIMEMANAGER_MINUTE, minute)
		info.func = TimeManagerAlarmMinuteDropDown_OnClick
		if minute == alarmMinute then
			info.checked = 1
			UIDropDownMenu_SetText(info.text, TimeManagerAlarmMinuteDropDown)
		else
			info.checked = nil
		end
		UIDropDownMenu_AddButton(info)
	end
end

function TimeManagerAlarmAMPMDropDown_Initialize()
	local info = UIDropDownMenu_CreateInfo()
	local pm = (Settings.militaryTime and Settings.alarmHour >= 12) or not Settings.alarmAM
	info.value = 1
	info.text = TIMEMANAGER_AM
	info.func = TimeManagerAlarmAMPMDropDown_OnClick
	if not pm then
		info.checked = 1
		UIDropDownMenu_SetText(info.text, TimeManagerAlarmAMPMDropDown)
	else
		info.checked = nil
	end
	UIDropDownMenu_AddButton(info)

	info.value = 0
	info.text = TIMEMANAGER_PM
	info.func = TimeManagerAlarmAMPMDropDown_OnClick
	if pm then
		info.checked = 1
		UIDropDownMenu_SetText(info.text, TimeManagerAlarmAMPMDropDown)
	else
		info.checked = nil
	end
	UIDropDownMenu_AddButton(info)
end

function TimeManagerAlarmHourDropDown_OnClick()
	UIDropDownMenu_SetSelectedValue(TimeManagerAlarmHourDropDown, this.value)
	local oldValue = Settings.alarmHour
	Settings.alarmHour = this.value
	if Settings.alarmHour ~= oldValue then
		TimeManager_StartCheckingAlarm()
	end
	_TimeManager_Setting_SetTime()
end

function TimeManagerAlarmMinuteDropDown_OnClick()
	UIDropDownMenu_SetSelectedValue(TimeManagerAlarmMinuteDropDown, this.value)
	local oldValue = Settings.alarmMinute
	Settings.alarmMinute = this.value
	if Settings.alarmMinute ~= oldValue then
		TimeManager_StartCheckingAlarm()
	end
	_TimeManager_Setting_SetTime()
end

function TimeManagerAlarmAMPMDropDown_OnClick()
	UIDropDownMenu_SetSelectedValue(TimeManagerAlarmAMPMDropDown, this.value)
	if this.value == 1 then
		if not Settings.alarmAM then
			Settings.alarmAM = true
			TimeManager_StartCheckingAlarm()
		end
	else
		if Settings.alarmAM then
			Settings.alarmAM = false
			TimeManager_StartCheckingAlarm()
		end
	end
	_TimeManager_Setting_SetTime()
end

function TimeManagerAlarmAMPMDropDown_OnShow()
	-- readjust the size of and reanchor TimeManagerAlarmAMPMDropDown and all frames below it
	TimeManagerAlarmAMPMDropDown:SetPoint("TOPLEFT", TimeManagerAlarmHourDropDown, "BOTTOMLEFT", 0, 5)
	TimeManagerAlarmMessageFrame:SetPoint("TOPLEFT", TimeManagerAlarmHourDropDown, "BOTTOMLEFT", 20, -23)
	TimeManagerAlarmEnabledButton:SetPoint("CENTER", TimeManagerFrame, "CENTER", -20, -69)
	TimeManagerMilitaryTimeCheck:SetPoint("TOPLEFT", TimeManagerFrame, "TOPLEFT", 174, -207)
end

function TimeManagerAlarmAMPMDropDown_OnHide()
	-- readjust the size of and reanchor TimeManagerAlarmAMPMDropDown and all frames below it
	TimeManagerAlarmAMPMDropDown:SetPoint("LEFT", TimeManagerAlarmHourDropDown, "RIGHT", -22, 0)
	TimeManagerAlarmMessageFrame:SetPoint("TOPLEFT", TimeManagerAlarmHourDropDown, "BOTTOMLEFT", 20, 0)
	TimeManagerAlarmEnabledButton:SetPoint("CENTER", TimeManagerFrame, "CENTER", -20, -50)
	TimeManagerMilitaryTimeCheck:SetPoint("TOPLEFT", TimeManagerFrame, "TOPLEFT", 174, -207)
end

function TimeManager_Update()
	TimeManager_UpdateTimeTicker()
	TimeManager_UpdateAlarmTime()
	TimeManagerAlarmEnabledButton_Update()
	if Settings.alarmMessage then
		TimeManagerAlarmMessageEditBox:SetText(Settings.alarmMessage)
	end
	TimeManagerMilitaryTimeCheck:SetChecked(Settings.militaryTime)
	TimeManagerLocalTimeCheck:SetChecked(Settings.localTime)
end

function TimeManager_UpdateAlarmTime()
	UIDropDownMenu_SetSelectedValue(TimeManagerAlarmHourDropDown, Settings.alarmHour)
	UIDropDownMenu_SetSelectedValue(TimeManagerAlarmMinuteDropDown, Settings.alarmMinute)
	UIDropDownMenu_SetText(format(TIMEMANAGER_MINUTE, Settings.alarmMinute), TimeManagerAlarmMinuteDropDown)
	if Settings.militaryTime then
		TimeManagerAlarmAMPMDropDown:Hide()
		UIDropDownMenu_SetText(format(TIMEMANAGER_24HOUR, Settings.alarmHour), TimeManagerAlarmHourDropDown)
	else
		TimeManagerAlarmAMPMDropDown:Show()
		UIDropDownMenu_SetText(Settings.alarmHour, TimeManagerAlarmHourDropDown)
		if Settings.alarmAM then
			UIDropDownMenu_SetSelectedValue(TimeManagerAlarmAMPMDropDown, 1)
			UIDropDownMenu_SetText(TIMEMANAGER_AM, TimeManagerAlarmAMPMDropDown)
		else
			UIDropDownMenu_SetSelectedValue(TimeManagerAlarmAMPMDropDown, 0)
			UIDropDownMenu_SetText(TIMEMANAGER_PM, TimeManagerAlarmAMPMDropDown)
		end
	end
end

function TimeManager_UpdateTimeTicker()
	TimeManagerFrameTicker:SetText(GameTime_GetTime(false))
end

function TimeManagerAlarmMessageEditBox_OnEnterPressed()
	this:ClearFocus()
end

function TimeManagerAlarmMessageEditBox_OnEscapePressed()
	this:ClearFocus()
end

function TimeManagerAlarmMessageEditBox_OnEditFocusLost()
	_TimeManager_Setting_Set("alarmMessage", TimeManagerAlarmMessageEditBox:GetText())
end

function TimeManagerAlarmEnabledButton_Update()
	if Settings.alarmEnabled then
		TimeManagerAlarmEnabledButton:SetText(TIMEMANAGER_ALARM_ENABLED)
		TimeManagerAlarmEnabledButton:SetTextFontObject("GameFontNormal")
		TimeManagerAlarmEnabledButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
		TimeManagerAlarmEnabledButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
	else
		TimeManagerAlarmEnabledButton:SetText(TIMEMANAGER_ALARM_DISABLED)
		TimeManagerAlarmEnabledButton:SetTextFontObject("GameFontHighlight")
		TimeManagerAlarmEnabledButton:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
		TimeManagerAlarmEnabledButton:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Disabled-Down")
	end
end

function TimeManagerAlarmEnabledButton_OnClick()
	_TimeManager_Setting_SetBool("alarmEnabled", not Settings.alarmEnabled)
	if Settings.alarmEnabled then
		PlaySound("igMainMenuOptionCheckBoxOn")
		TimeManager_StartCheckingAlarm()
	else
		PlaySound("igMainMenuOptionCheckBoxOff")
		if TimeManagerClockButton.alarmFiring then
			TimeManager_TurnOffAlarm()
		end
	end
	TimeManagerAlarmEnabledButton_Update()
end

function TimeManagerMilitaryTimeCheck_OnClick()
	TimeManager_ToggleTimeFormat()
	if this:GetChecked() then
		PlaySound("igMainMenuOptionCheckBoxOn")
	else
		PlaySound("igMainMenuOptionCheckBoxOff")
	end
end

function TimeManager_ToggleTimeFormat()
	local alarmHour = Settings.alarmHour
	if Settings.militaryTime then
		_TimeManager_Setting_SetBool("militaryTime", false)
		Settings.alarmAM = alarmHour < 12
		if alarmHour > 12 then
			Settings.alarmHour = alarmHour - 12
		elseif alarmHour == 0 then
			Settings.alarmHour = 12
		end
	else
		_TimeManager_Setting_SetBool("militaryTime", true)
		if Settings.alarmAM and alarmHour == 12 then
			Settings.alarmHour = 0
		elseif not Settings.alarmAM and alarmHour < 12 then
			Settings.alarmHour = alarmHour + 12
		end
	end
	_TimeManager_Setting_SetTime()
	TimeManager_UpdateAlarmTime()
	-- TimeManagerFrame_OnUpdate will pick up the time ticker change
	-- TimeManagerClockButton_OnUpdate will pick up the clock change
end

function TimeManagerLocalTimeCheck_OnClick()
	TimeManager_ToggleLocalTime()
	-- since we're changing which time type we're checking, we need to check the alarm now
	TimeManager_StartCheckingAlarm()
	if this:GetChecked() then
		PlaySound("igMainMenuOptionCheckBoxOn")
	else
		PlaySound("igMainMenuOptionCheckBoxOff")
	end
end

function TimeManager_ToggleLocalTime()
	_TimeManager_Setting_SetBool("localTime", not Settings.localTime)
	-- TimeManagerFrame_OnUpdate will pick up the time ticker change
	-- TimeManagerClockButton_OnUpdate will pick up the clock change
end

-- TimeManagerClockButton

function TimeManagerClockButton_Show()
	TimeManagerClockButton:Show()
end

function TimeManagerClockButton_Hide()
	TimeManagerClockButton:Hide()
end

function TimeManagerClockButton_OnLoad()
	this:RegisterEvent("ADDON_LOADED")
	this:SetFrameLevel(this:GetFrameLevel() + 2)
	TimeManagerClockButton_Show()
end

function TimeManagerClockButton_OnEvent()
	TimeManagerClockButton_Update()
	if Settings.alarmEnabled then
		TimeManager_StartCheckingAlarm()
	end
end

function TimeManagerClockButton_Update()
	TimeManagerClockTicker:SetText(GameTime_GetTime(false))
end

function TimeManagerClockButton_OnEnter()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	TimeManagerClockButton:SetScript("OnUpdate", TimeManagerClockButton_OnUpdateWithTooltip)
end

function TimeManagerClockButton_OnLeave()
	GameTooltip:Hide()
	TimeManagerClockButton:SetScript("OnUpdate", TimeManagerClockButton_OnUpdate)
end

function TimeManagerClockButton_OnClick()
	if this.alarmFiring then
		PlaySound("igMainMenuQuit")
		TimeManager_TurnOffAlarm()
	elseif not GameTimeFrame:IsShown() then
		TimeManager_Toggle()
	end
end

function TimeManagerClockButton_OnUpdate()
	TimeManagerClockButton_Update()
	if TimeManagerClockButton.checkAlarm and Settings.alarmEnabled then
		TimeManager_CheckAlarm(arg1)
	end
end

function TimeManagerClockButton_OnUpdateWithTooltip()
	TimeManagerClockButton_OnUpdate(this, arg1)
	TimeManagerClockButton_UpdateTooltip()
end

function TimeManager_ShouldCheckAlarm()
	return TimeManagerClockButton.checkAlarm and Settings.alarmEnabled
end

function TimeManager_StartCheckingAlarm()
	TimeManagerClockButton.checkAlarm = true

	-- set the time to play the warning sound
	local alarmTime = _TimeManager_ComputeMinutes(Settings.alarmHour, Settings.alarmMinute, Settings.militaryTime, Settings.alarmAM)
	local warningTime = alarmTime + WARNING_SOUND_TRIGGER_OFFSET
	-- max minutes per day = 24*60 = 1440
	if warningTime < 0 then
		warningTime = warningTime + 1440
	elseif warningTime > 1440 then
		warningTime = warningTime - 1440
	end
	TimeManagerClockButton.warningTime = warningTime
	TimeManagerClockButton.checkAlarmWarning = true
	-- since game time isn't available in seconds, we have to keep track of the previous minute
	-- in order to play our alarm warning sound at the right time
	TimeManagerClockButton.currentMinute = _TimeManager_GetCurrentMinutes(Settings.localTime)
	TimeManagerClockButton.currentMinuteCounter = 0
end

function TimeManager_CheckAlarm()
	local currTime = _TimeManager_GetCurrentMinutes(Settings.localTime)
	local alarmTime = _TimeManager_ComputeMinutes(Settings.alarmHour, Settings.alarmMinute, Settings.militaryTime, Settings.alarmAM)

	-- check for the warning sound
	local clockButton = TimeManagerClockButton
	if clockButton.checkAlarmWarning then
		if clockButton.currentMinute ~= currTime then
			clockButton.currentMinute = currTime
			clockButton.currentMinuteCounter = 0
		end
		local secOffset = floor(clockButton.currentMinuteCounter) * SEC_TO_MINUTE_FACTOR
		if (currTime + secOffset) == clockButton.warningTime then
			TimeManager_FireAlarmWarning()
		end
		clockButton.currentMinuteCounter = clockButton.currentMinuteCounter + arg1
	end
	-- check for the alarm sound
	if currTime == alarmTime then
		TimeManager_FireAlarm()
	end
end

function TimeManager_FireAlarmWarning()
	TimeManagerClockButton.checkAlarmWarning = false
	PlaySoundFile("Interface\\AddOns\\TimeManager\\Sounds\\AlarmClockWarning1.wav")
end

function TimeManager_FireAlarm()
	TimeManagerClockButton.alarmFiring = true
	TimeManagerClockButton.checkAlarm = false

	-- do a bunch of crazy stuff to get the player's attention
	if Settings.alarmMessage and gsub(Settings.alarmMessage, "%s", "") ~= "" then
		local info = ChatTypeInfo["SYSTEM"]
		DEFAULT_CHAT_FRAME:AddMessage(Settings.alarmMessage, info.r, info.g, info.b, info.id)
		info = ChatTypeInfo["RAID_WARNING"]
		RaidWarningFrame:AddMessage(Settings.alarmMessage, info.r, info.g, info.b, info.id)
	end
	PlaySoundFile("Interface\\AddOns\\TimeManager\\Sounds\\AlarmClockWarning2.wav")
	UIFrameFlash(TimeManagerAlarmFiredTexture, 0.5, 0.5, -1)
	-- show the clock if necessary, but record its current state so it can return to that state after
	-- the player turns the alarm off
	TimeManagerClockButton.prevShown = TimeManagerClockButton:IsShown()
	TimeManagerClockButton:Show()
end

function TimeManager_TurnOffAlarm()
	UIFrameFlashStop(TimeManagerAlarmFiredTexture)
	if not TimeManagerClockButton.prevShown then
		TimeManagerClockButton:Hide()
	end

	TimeManagerClockButton.alarmFiring = false
end

function TimeManager_IsAlarmFiring()
	return TimeManagerClockButton.alarmFiring
end

function TimeManagerClockButton_UpdateTooltip()
	GameTooltip:ClearLines()

	if TimeManagerClockButton.alarmFiring then
		if Settings.alarmMessage and gsub(Settings.alarmMessage, "%s", "") ~= "" then
			GameTooltip:AddLine(Settings.alarmMessage, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			GameTooltip:AddLine(" ")
		end
		GameTooltip:AddLine(TIMEMANAGER_ALARM_TOOLTIP_TURN_OFF)
	else
		GameTime_UpdateTooltip()
		if not GameTimeFrame:IsShown() then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(TIMEMANAGER_TOOLTIP_TOGGLE_CLOCK_SETTINGS)
		end
	end

	-- readjust tooltip size
	GameTooltip:Show()
end

-- StopwatchFrame

function Stopwatch_Toggle()
	if StopwatchFrame:IsShown() then
		StopwatchFrame:Hide()
	else
		StopwatchFrame:Show()
	end
end

function Stopwatch_StartCountdown(hour, minute, second)
	local sec = 0
	if hour then
		sec = hour * 3600
	end
	if minute then
		sec = sec + minute * 60
	end
	if second then
		sec = sec + second
	end
	if sec == 0 then
		Stopwatch_Toggle()
		return
	end
	if sec > MAX_TIMER_SEC then
		StopwatchTicker.timer = MAX_TIMER_SEC
	elseif sec < 0 then
		StopwatchTicker.timer = 0
	else
		StopwatchTicker.timer = sec
	end
	StopwatchTicker_Update()
	StopwatchTicker.reverse = sec > 0
	StopwatchFrame:Show()
end

function Stopwatch_ShowCountdown(hour, minute, second)
	local sec = 0
	if hour then
		sec = hour * 3600
	end
	if minute then
		sec = sec + minute * 60
	end
	if second then
		sec = sec + second
	end
	if sec == 0 then
		Stopwatch_Toggle()
		return
	end
	if sec > MAX_TIMER_SEC then
		StopwatchTicker.timer = MAX_TIMER_SEC
	elseif sec < 0 then
		StopwatchTicker.timer = 0
	else
		StopwatchTicker.timer = sec
	end
	StopwatchTicker_Update()
	StopwatchTicker.reverse = sec > 0
	StopwatchFrame:Show()
end

function Stopwatch_FinishCountdown()
	Stopwatch_Clear()
	PlaySoundFile("Interface\\AddOns\\TimeManager\\Sounds\\AlarmClockWarning3.wav")
end

function StopwatchCloseButton_OnClick()
	PlaySound("igMainMenuQuit")
	StopwatchFrame:Hide()
end

function StopwatchFrame_OnLoad()
	this:RegisterEvent("ADDON_LOADED")
	this:RegisterEvent("PLAYER_LOGOUT")
	this:RegisterForDrag("LeftButton")
	StopwatchTabFrame:SetAlpha(0)
	Stopwatch_Clear()
end

function StopwatchFrame_OnEvent(event)
	if event == "ADDON_LOADED" then
		local name = arg1
		if name == "TimeManager" then
			if not StopwatchOptions then
				StopwatchOptions = {}
			end

			if StopwatchOptions.position then
				StopwatchFrame:ClearAllPoints()
				StopwatchFrame:SetPoint("CENTER", "UIParent", "BOTTOMLEFT", StopwatchOptions.position.x, StopwatchOptions.position.y)
				StopwatchFrame:SetUserPlaced(true)
			else
				StopwatchFrame:SetPoint("TOPRIGHT", "UIParent", "TOPRIGHT", -250, -300)
			end
		end
	elseif event == "PLAYER_LOGOUT" then
		if StopwatchFrame:IsUserPlaced() then
			if not StopwatchOptions.position then
				StopwatchOptions.position = {}
			end
			StopwatchOptions.position.x, StopwatchOptions.position.y = StopwatchFrame:GetCenter()
			StopwatchFrame:SetUserPlaced(false)
		else
			StopwatchOptions.position = nil
		end
	end
end

function StopwatchFrame_OnUpdate()
	if this.prevMouseIsOver then
		if not MouseIsOver(this, 20, -8, -8, 20) then
			UIFrameFadeOut(StopwatchTabFrame, CHAT_FRAME_FADE_TIME)
			this.prevMouseIsOver = false
		end
	else
		if MouseIsOver(this, 20, -8, -8, 20) then
			UIFrameFadeIn(StopwatchTabFrame, CHAT_FRAME_FADE_TIME)
			this.prevMouseIsOver = true
		end
	end
end

function StopwatchFrame_OnShow()
	TimeManagerStopwatchCheck:SetChecked(1)
end

function StopwatchFrame_OnHide()
	UIFrameFadeRemoveFrame(StopwatchTabFrame)
	StopwatchTabFrame:SetAlpha(0)
	this.prevMouseIsOver = false
	TimeManagerStopwatchCheck:SetChecked(nil)
end

function StopwatchFrame_OnMouseDown()
	this:SetScript("OnUpdate", nil)
end

function StopwatchFrame_OnMouseUp()
	this:SetScript("OnUpdate", StopwatchFrame_OnUpdate)
end


function StopwatchFrame_OnDragStart()
	this:StartMoving()
end

function StopwatchFrame_OnDragStop()
	StopwatchFrame_OnMouseUp() -- OnMouseUp won't fire if OnDragStart fired after OnMouseDown
	this:StopMovingOrSizing()
end

function StopwatchTicker_OnUpdate()
	if StopwatchTicker.reverse then
		StopwatchTicker.timer = StopwatchTicker.timer - arg1
		if StopwatchTicker.timer <= 0 then
			Stopwatch_FinishCountdown()
			return
		end
	elseif StopwatchTicker.timer then
		StopwatchTicker.timer = StopwatchTicker.timer + arg1
	else
		StopwatchTicker.timer = 0
	end
	StopwatchTicker_Update()
end

function StopwatchTicker_Update()
	local timer = StopwatchTicker.timer
	local hour = min(floor(timer * SEC_TO_HOUR_FACTOR), 99)
	local minute = mod(timer * SEC_TO_MINUTE_FACTOR, 60)
	local second = mod(timer, 60)
	StopwatchTickerHour:SetText(format(STOPWATCH_TIME_UNIT, hour))
	StopwatchTickerMinute:SetText(format(STOPWATCH_TIME_UNIT, minute))
	StopwatchTickerSecond:SetText(format(STOPWATCH_TIME_UNIT, second))
end

function Stopwatch_Play()
	StopwatchPlayPauseButton.playing = true
	StopwatchTicker:SetScript("OnUpdate", StopwatchTicker_OnUpdate)
	StopwatchPlayPauseButton:SetNormalTexture("Interface\\AddOns\\TimeManager\\Textures\\PauseButton")
end


function Stopwatch_Pause()
	StopwatchPlayPauseButton.playing = false
	StopwatchTicker:SetScript("OnUpdate", nil)
	StopwatchPlayPauseButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
end

function Stopwatch_IsPlaying()
	return StopwatchPlayPauseButton.playing
end

function Stopwatch_Clear()
	StopwatchTicker.timer = 0
	StopwatchTicker.reverse = false
	StopwatchTicker:SetScript("OnUpdate", nil)
	StopwatchTicker_Update()
	StopwatchPlayPauseButton.playing = false
	StopwatchPlayPauseButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
end

function StopwatchResetButton_OnClick()
	Stopwatch_Clear()
	PlaySound("igMainMenuOptionCheckBoxOff")
end

function StopwatchPlayPauseButton_OnClick()
	if this.playing then
		Stopwatch_Pause()
		PlaySound("igMainMenuOptionCheckBoxOff")
	else
		Stopwatch_Play()
		PlaySound("igMainMenuOptionCheckBoxOn")
	end
end

SlashCmdList["STOPWATCH"] = function(msg)
	local _, _, text = strfind(msg, "%s*([^%s]+)%s*")
	if text then
		text = strlower(text)

		-- in any of the following cases, the stopwatch will be shown
		StopwatchFrame:Show()

		-- try to match a command
		local function MatchCommand(param, text)
			local i, compare
			i = 1
			repeat
				compare = _G[param .. i]
				if compare and compare == text then
					return true
				end
				i = i + 1
			until not compare
			return false
		end
		if MatchCommand("SLASH_STOPWATCH_PARAM_PLAY", text) then
			Stopwatch_Play()
			return
		end
		if MatchCommand("SLASH_STOPWATCH_PARAM_PAUSE", text) then
			Stopwatch_Pause()
			return
		end
		if MatchCommand("SLASH_STOPWATCH_PARAM_STOP", text) then
			Stopwatch_Clear()
			return
		end
		-- try to match a countdown
		-- kinda ghetto, but hey, it's simple and it works =)
		local _, _, hour, minute, second = strfind(msg, "(%d+):(%d+):(%d+)")
		if not hour then
			_, _, minute, second = strfind(msg, "(%d+):(%d+)")
			if not minute then
				_, _, second = strfind(msg, "(%d+)")
			end
		end
		Stopwatch_StartCountdown(tonumber(hour), tonumber(minute), tonumber(second))
	else
		Stopwatch_Toggle()
	end
end

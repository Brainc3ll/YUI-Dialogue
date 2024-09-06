local _, addon = ...
local API = addon.API;
local GetDBValue = addon.GetDBValue;


local DBKEY_POSITION = "WidgetManagerPosition";

local Round = API.Round;
local CreateFrame = CreateFrame;
local GetCursorPosition = GetCursorPosition;
local UIParent = UIParent;

local MainAnchor = CreateFrame("Frame");
MainAnchor:SetSize(8, 8);
MainAnchor:SetClampedToScreen(true);
MainAnchor:SetPoint("CENTER", UIParent, "LEFT", 24, 32);
MainAnchor:Hide();

local WidgetManager = CreateFrame("Frame");
addon.WidgetManager = WidgetManager;


local DragFrame = CreateFrame("Frame");
do  --Emulate Drag gesture
    function DragFrame:StopWatching()
        self:SetParent(nil);
        self:SetScript("OnUpdate", nil);
        self.t = nil;
        self.x, self.y = nil, nil;
        self.x0, self.y0 = nil, nil;
        self.ownerX, self.ownerY = nil, nil;
        self.delta = nil;
        self:UnregisterEvent("GLOBAL_MOUSE_UP");

        if self.owner then
            if self.owner.isMoving then
                --This method may get called during PreDrag, when the owner isn't moving
                if self.owner.SavePosition then
                    self.owner:SavePosition();
                end
                if self.owner.OnDragStop then
                    self.owner:OnDragStop();
                end
            end
            self.owner.isMoving = nil;
            self.owner = nil;
        end
    end

    function DragFrame:StartWatching(owner)
        --Start watching Drag gesture when MouseDown on owner
        self:SetParent(owner);
        self.owner = owner;

        if not owner:IsVisible() then
            self:StopWatching();
            return
        end

        self.x0, self.y0 = GetCursorPosition();
        self.t = 0;
        self:SetScript("OnUpdate", self.OnUpdate_PreDrag);
        self:RegisterEvent("GLOBAL_MOUSE_UP");
    end

    function DragFrame:SetOwnerPosition()
        self.x , self.y = GetCursorPosition();
        self.x = (self.x - self.x0) / self.scale;
        self.y = (self.y - self.y0) / self.scale;
        self.owner:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.x + self.ownerX, self.y + self.ownerY);
    end

    function DragFrame:OnUpdate_PreDrag(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.016 then
            self.t = 0;
            self.x , self.y = GetCursorPosition();
            self.delta = (self.x - self.x0)*(self.x - self.x0) + (self.y - self.y0)*(self.y - self.y0);
            if self.delta >= 16 then     --Threshold
                --Actual Dragging start
                self.owner.isMoving = true;
                self.scale = self.owner:GetEffectiveScale();
                self.x0, self.y0 = GetCursorPosition();
                self.ownerX = self.owner:GetLeft();
                self.ownerY = self.owner:GetBottom();
                self.owner:ClearAllPoints();
                if self.owner.OnDragStart then
                    self.owner:OnDragStart();
                end
                self:SetOwnerPosition();
                self:SetScript("OnUpdate", self.OnUpdate_OnDrag);
            end
        end
    end

    function DragFrame:OnUpdate_OnDrag(elapsed)
        self.t = self.t + elapsed;
        if self.t > 0.008 then
            self.t = 0;
            self:SetOwnerPosition();
        end
    end

    DragFrame:SetScript("OnHide", function()
        DragFrame:StopWatching()
    end);

    DragFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "GLOBAL_MOUSE_UP" then
            DragFrame:StopWatching();
        end
    end);
end

do  --Draggable Widget
    local WidgetBaseMixin = {};

    function WidgetBaseMixin:SavePosition()
        if not self.dbkeyPosition then return end;

        local x = self:GetLeft();
        local _, y = self:GetCenter();

        if not x and y then return end;

        local position = {
            Round(x),
            Round(y);
        };

        addon.SetDBValue(self.dbkeyPosition, position);
        addon.SettingsUI:RequestUpdate();
    end

    function WidgetBaseMixin:ResetPosition()
        if not self.dbkeyPosition then return end;

        if self:IsUsingCustomPosition() then
            addon.SetDBValue(self.dbkeyPosition, nil);
        end
        self:LoadPosition();
        addon.SettingsUI:RequestUpdate();
    end

    function WidgetBaseMixin:IsUsingCustomPosition()
        if not self.dbkeyPosition then return end;
        return GetDBValue(self.dbkeyPosition) ~= nil
    end

    function WidgetBaseMixin:LoadPosition()
        if not self.dbkeyPosition then return end;
        local position = GetDBValue(self.dbkeyPosition);
        self:ClearAllPoints();
        if position then
            self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", position[1], position[2]);
        else
            if self.isChainable and self:IsVisible() then
                WidgetManager:ChainAdd(self);
            else
                self:SetPoint("LEFT", nil, "LEFT", 24, 32);
            end
        end
    end

    local function WidgetBaseMixin_OnMouseDown(self, button)
        if button == "LeftButton" then
            DragFrame:StartWatching(self);
        end

        if self.OnMouseDown then
            self:OnMouseDown(button);
        end
    end

    local function WidgetBaseMixin_OnMouseUp(self, button)
        if self.OnMouseUp then
            self:OnMouseUp(button);
        end
    end

    function WidgetManager:CreateWidget(dbkeyPosition)
        local f = CreateFrame("Frame");
        f:SetClampedToScreen(true);
        f:SetMovable(true);
        API.Mixin(f, WidgetBaseMixin);
        f.dbkeyPosition = dbkeyPosition;
        f:SetScript("OnMouseDown", WidgetBaseMixin_OnMouseDown);
        f:SetScript("OnMouseUp", WidgetBaseMixin_OnMouseUp);
        return f
    end
end

do  --Auto Close Button
    local PI = math.pi;

    local function Countdown_OnUpdate(self, elapsed)
        self.t = self.t + elapsed;
        self.progress = self.t / self.duration;

        if self.progress >= 1 then
            self.progress = nil;
            self.t = nil;
            self:SetScript("OnUpdate", nil);
            self.Swipe1:Hide();
            self.isCountingDown = nil;
            if self.owner.OnCountdownFinished then
                self.owner:OnCountdownFinished();
            end
        elseif self.progress >= 0.5 then
            self.SwipeMask1:SetRotation((self.progress/0.5 - 1) * PI);
            self.Swipe2:Hide();
        else
            self.SwipeMask2:SetRotation((self.progress/0.5 - 1) * PI);
        end
    end

    local AutoCloseButtonMixin = {};

    function AutoCloseButtonMixin:SetCountdown(second)
        self.duration = second;
        self.t = 0;
        self.Swipe1:Show();
        self.Swipe2:Show();
        self.SwipeMask1:SetRotation(0);
        self.SwipeMask2:SetRotation(-PI);
        self.isCountingDown = true;
        self:SetScript("OnUpdate", Countdown_OnUpdate);
    end

    function AutoCloseButtonMixin:StopCountdown()
        if self.isCountingDown then
            self:SetScript("OnUpdate", nil);
            self.t = nil;
            self.progress = nil;
            self.isCountingDown = nil;
            self.Swipe1:Hide();
            self.Swipe2:Hide();
        end
    end

    function AutoCloseButtonMixin:PauseAutoCloseTimer(state)
        if self.isCountingDown then
            if state then
                self:SetScript("OnUpdate", nil);
            else
                self:SetScript("OnUpdate", Countdown_OnUpdate);
            end
        end
    end

    function AutoCloseButtonMixin:SetTheme(themeID)
        if themeID == 1 then
            self.CloseButtonTexture:SetTexCoord(0, 0.25, 0, 0.25);
            self.Swipe1:SetTexCoord(0.125, 0.25, 0.25, 0.5)
            self.Swipe2:SetTexCoord(0, 0.125, 0.25, 0.5);
        else
            self.CloseButtonTexture:SetTexCoord(0.25, 0.5, 0, 0.25);
            self.Swipe1:SetTexCoord(0.375, 0.5, 0.25, 0.5)
            self.Swipe2:SetTexCoord(0.25, 0.375, 0.25, 0.5);
        end
    end

    function AutoCloseButtonMixin:OnEnter()
        self:PauseAutoCloseTimer(true);
        if self.owner.OnEnter then
            self.owner:OnEnter()
        end
    end

    function AutoCloseButtonMixin:OnLeave()
        self:PauseAutoCloseTimer(false);
        if self.owner.OnLeave then
            self.owner:OnLeave()
        end
    end

    function AutoCloseButtonMixin:OnClick()
        if self.owner.Close then
            self.owner:Close(true);
        end
    end

    function WidgetManager:CreateAutoCloseButton(parent)
        local f = CreateFrame("Button", nil, parent);
        API.Mixin(f, AutoCloseButtonMixin);
        f.owner = parent;

        local CLOSE_BUTTON_SIZE = 34;
        f:SetSize(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE);

        local bt = f:CreateTexture(nil, "OVERLAY");
        f.CloseButtonTexture = bt;

        bt:SetSize(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE);
        bt:SetPoint("CENTER", f, "CENTER", 0, 0);

        local function CreateSwipe(isRight)
            local sw = f:CreateTexture(nil, "OVERLAY", nil, 1);
            sw:SetSize(CLOSE_BUTTON_SIZE/2, CLOSE_BUTTON_SIZE);
            if isRight then
                sw:SetPoint("LEFT", bt, "CENTER", 0, 0);
                sw:SetTexCoord(0.375, 0.5, 0.25, 0.5);
            else
                sw:SetPoint("RIGHT", bt, "CENTER", 0, 0);
                sw:SetTexCoord(0.25, 0.375, 0.25, 0.5);
            end
            local mask = f:CreateMaskTexture(nil, "OVERLAY", nil, 1);
            sw:AddMaskTexture(mask);
            mask:SetTexture("Interface/AddOns/DialogueUI/Art/BasicShapes/Mask-RightWhite", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE");
            mask:SetSize(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE);
            mask:SetPoint("CENTER", bt, "CENTER", 0, 0);
            sw:Hide();
            return sw, mask
        end

        f.Swipe1, f.SwipeMask1 = CreateSwipe(true);
        f.Swipe2, f.SwipeMask2 = CreateSwipe();
        f.SwipeMask2:SetRotation(-PI);

        local highlight = f:CreateTexture(nil, "HIGHLIGHT");
        highlight:SetSize(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE);
        highlight:SetPoint("CENTER", f, "CENTER", 0, 0);

        local file = "Interface/AddOns/DialogueUI/Art/Theme_Shared/WidgetCloseButton.png";
        bt:SetTexture(file);
        highlight:SetTexture(file);
        highlight:SetTexCoord(0.5, 0.75, 0, 0.25);
        highlight:SetBlendMode("ADD");
        highlight:SetVertexColor(0.5, 0.5, 0.5);

        f.Swipe1:SetTexture(file);
        f.Swipe2:SetTexture(file);

        f:SetTheme(2);
        f:SetScript("OnEnter", f.OnEnter);
        f:SetScript("OnLeave", f.OnLeave);
        f:SetScript("OnClick", f.OnClick);
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp");

        return f
    end
end

do  --Position Chain, Dock
    --New widget will be put to the top
    local GAP_Y = 20;

    local pairs = pairs;
    local ipairs = ipairs;
    local ChainedFrames = {};
    local ChainIndex = 0;

    function WidgetManager:ChainContain(widget)
        if ChainedFrames[widget] then
            return true
        else
            return false
        end
    end

    function WidgetManager:ChainAdd(widget)
        if not self:ChainContain(widget) then
            ChainIndex = ChainIndex + 1;
            ChainedFrames[widget] = ChainIndex;
            self:ChainLayout();
            return true
        end
    end

    function WidgetManager:ChainRemove(widget)
        widget.currentPosition = nil;

        if self:ChainContain(widget) then
            ChainedFrames[widget] = nil;
            self:ChainLayout();
            return true
        end
    end

    function WidgetManager:ChainLayout(animate)
        local widgets = {};
        local n = 0;

        for widget, index in pairs(ChainedFrames) do
            n = n + 1;
            widget.order = index;
            widgets[n] = widget;
        end

        self.widgets = widgets;
        self.numWidgets = n;

        if n == 0 then return end;

        table.sort(widgets, function(a, b)
            return a.order < b.order
        end);

        local offsetY = 0;

        --[[    --Use BOTTOMLEFT as anchor
        for i, widget in ipairs(widgets) do
            widget.targetPosition = offsetY;
            widget.anchorDirty = true;
            offsetY = offsetY + Round(widget:GetHeight()) + GAP_Y;
        end
        --]]

        --Use LEFT as anchor
        for i, widget in ipairs(widgets) do
            if i > 0 then
                offsetY = Round(offsetY + widget:GetHeight() * 0.5)
            end
            widget.targetPosition = offsetY;
            widget.anchorDirty = true;
            offsetY = Round(offsetY + widget:GetHeight() * 0.5 + GAP_Y);
        end

        animate = true;
        self:ChainPosition(animate);
    end

    local function ChainPosition_OnUpdate(self, elapsed)
        local complete = true;
        local a = 16 * elapsed;
        local diff;
        local delta;
        local widget;

        for i = 1, self.numWidgets do
            widget = self.widgets[i];
            if widget.currentPosition then
                diff = widget.targetPosition - widget.currentPosition;
                if diff ~= 0 then
                    delta = elapsed * 16 * diff;
                    if diff >= 0 and (diff < 1 or (widget.currentPosition + delta >= widget.targetPosition)) then
                        widget.currentPosition = widget.targetPosition;
                        complete = complete and true;
                    elseif diff <= 0 and (diff > -1 or (widget.currentPosition + delta <= widget.targetPosition)) then
                        widget.currentPosition = widget.targetPosition;
                        complete = complete and true;
                    else
                        widget.currentPosition = widget.currentPosition + delta;
                        complete = false;
                    end

                    if widget.anchorDirty then
                        widget.anchorDirty = nil;
                        widget:ClearAllPoints();
                    end

                    widget:SetPoint("LEFT", MainAnchor, "BOTTOMLEFT", 0, widget.currentPosition);
                end
            else
                if widget.anchorDirty then
                    widget.anchorDirty = nil;
                    widget:ClearAllPoints();
                end
                widget:SetPoint("LEFT", MainAnchor, "BOTTOMLEFT", 0, widget.targetPosition);
                widget.currentPosition = widget.targetPosition;
            end
        end

        if complete then
            self:SetScript("OnUpdate", nil);
        end
    end

    function WidgetManager:ChainPosition(animate)
        if animate  then
            self:SetScript("OnUpdate", ChainPosition_OnUpdate);
        else
            self:SetScript("OnUpdate", nil);
            local widget;
            local y;
            for i = 1, self.numWidgets do
                widget = self.widgets[i];
                if widget.anchorDirty then
                    widget.anchorDirty = nil;
                    widget:ClearAllPoints();
                end
                y = widget.targetPosition;
                widget:SetPoint("LEFT", MainAnchor, "BOTTOMLEFT", 0, y);
                widget.currentPosition = y;
            end
        end
    end
end

do  --Event Handler
    --Events and their handlers are set in other Widget sub-modules
    function WidgetManager:OnEvent(event, ...)
        if self[event] then
            self[event](self, ...);
        end
    end
    WidgetManager:SetScript("OnEvent", WidgetManager.OnEvent);
end
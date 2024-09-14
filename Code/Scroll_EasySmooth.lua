-- Create a simple smooth scroll frame

local _, addon = ...
local API = addon.API;
local DeltaLerp = API.DeltaLerp;
local SCROLL_BLEND_SPEED = 0.15;    --0.2


local ScrollFrameMixin = {};
do
    function ScrollFrameMixin:OnUpdate_Easing(elapsed)
        self.value = DeltaLerp(self.value, self.scrollTarget, self.blendSpeed, elapsed);

        if (self.value - self.scrollTarget) > -0.4 and (self.value - self.scrollTarget) < 0.4 then
            --print("complete")
            self.value = self.scrollTarget;
            self:SetScript("OnUpdate", nil);

            if self.value == 0 then
                --at top
                --self.borderTop:Hide();
                --FadeFrame(self.borderTop, 0.25, 0);
            elseif self.value == self.range then
                --at bottom
                --self.borderBottom:Hide();
                --FadeFrame(self.borderBottom, 0.25, 0);
            end

            if self.isRecyclable then
                --self:DebugGetCount();
                self.recycleTimer = 1;
            end
        end

        if self.isRecyclable then
            self.recycleTimer = self.recycleTimer + elapsed;
            if self.recycleTimer > 0.033 then
                self.recycleTimer = 0;
                self:UpdateView();
            end
        end

        self:SetOffset(self.value);
    end

    function ScrollFrameMixin:SetOffset(value)
        self.topDividerAlpha = value/24;
        if self.topDividerAlpha > 1 then
            self.topDividerAlpha = 1;
        elseif self.topDividerAlpha < 0 then
            self.topDividerAlpha = 0;
        end
        self.borderTop:SetAlpha(self.topDividerAlpha);

        self.bottomDividerAlpha = (self.range - value)/24;
        if self.bottomDividerAlpha > 1 then
            self.bottomDividerAlpha = 1;
        elseif self.bottomDividerAlpha < 0 then
            self.bottomDividerAlpha = 0;
        end

        self.borderBottom:SetAlpha(self.bottomDividerAlpha);
        self.value = value;
        self:SetVerticalScroll(value);
    end

    function ScrollFrameMixin:ResetScroll()
        self:SetScript("OnUpdate", nil);
        self:SetOffset(0);
        self.scrollTarget = 0;
    end

    function ScrollFrameMixin:GetScrollTarget()
        return self.scrollTarget or self:GetVerticalScroll()
    end

    function ScrollFrameMixin:ScrollBy(deltaValue)
        local offset = self:GetVerticalScroll();
        self:ScrollTo(offset + deltaValue);
    end

    function ScrollFrameMixin:SetScrollRange(range)
        self.range = range;
    end

    function ScrollFrameMixin:ScrollTo(value)
        value = API.Clamp(value, 0, self.range);
        if value ~= self.scrollTarget then
            self.scrollTarget = value;
            self:SetScript("OnUpdate", self.OnUpdate_Easing);
            self.recycleTimer = 0;
            if self.range > 0 then
                self:UpdateOverlapBorderVisibility();
            end
        end
    end

    function ScrollFrameMixin:ScrollToTop()
        self:ScrollTo(0);
        self.borderTop:Hide();
        if self.range > 0 and self.useBottom then
            self.borderBottom:Show();
        end
    end

    function ScrollFrameMixin:ScrollToBottom()
        self:ScrollTo(self.range);
        self.borderBottom:Hide();
        if self.range > 0 and self.useTop then
            self.borderTop:Show();
        end
    end

    function ScrollFrameMixin:IsAtPageTop()
        local offset = self:GetVerticalScroll();
        return self.value <= 0.1
    end

    function ScrollFrameMixin:IsAtPageBottom()
        local offset = self:GetVerticalScroll();
        return self.value + 0.1 >= (self.range or 0)
    end

    function ScrollFrameMixin:SetBlendSpeed(blendSpeed)
        self.blendSpeed = blendSpeed or SCROLL_BLEND_SPEED
    end

    function ScrollFrameMixin:SetUseOverlapBorder(useTop, useBottom)
        self.useTop = useTop;
        self.useBottom = useBottom;
        self:UpdateOverlapBorderVisibility();
    end

    function ScrollFrameMixin:UpdateOverlapBorderVisibility()
        self.borderTop:SetShown(self.useTop);
        self.borderBottom:SetShown(self.useBottom);
    end
end

local function InitEasyScrollFrame(scrollFrame, borderTop, borderBottom)
    scrollFrame.value = 0;
    scrollFrame.range = 0;
    scrollFrame.borderTop = borderTop;
    scrollFrame.borderBottom = borderBottom;
    scrollFrame.blendSpeed = SCROLL_BLEND_SPEED;
    API.Mixin(scrollFrame, ScrollFrameMixin);
    return scrollFrame
end
addon.InitEasyScrollFrame = InitEasyScrollFrame;


--Recyclable Content ScrollFrame
do
    local ipairs = ipairs;

    local RecyclableFrameMixin = {};

    function RecyclableFrameMixin:GetViewSize()
        return self:GetHeight()
    end

    function RecyclableFrameMixin:SetContent(content)
        --Content = {
        --    [index] = {
        --        offset =  offsetY
        --        otherData...
        --    },
        --}

        self.content = content;

        --Objects are released from a different path
        self.bins = {};
        self.contentIndexObject = {};
    end

    function RecyclableFrameMixin:ClearContent()
        self.content = nil;
        self.bins = nil;
        self.contentIndexObject = nil;
    end

    function RecyclableFrameMixin:AcquireAndSetData(data)
        local type = self:GetDataRequiredObjectType(data);
        local obj;

        if self.bins[type] and self.bins[type].count > 0 then
            local b = self.bins[type];
            obj = b[b.count];
            b[b.count] = nil;
            b.count = b.count - 1;
        end

        return self:SetObjectData(obj, data);
    end

    function RecyclableFrameMixin:RecycleObject(contentIndex)
        local obj = self.contentIndexObject[contentIndex];

        obj:Hide();
        obj:ClearAllPoints();

        local type = obj:GetObjectType();
        local b = self.bins[type];
        if not b then
            b = {
                count = 0,
            };
            self.bins[type] = b;
        end

        b.count = b.count + 1;
        b[b.count] = obj;
        self.contentIndexObject[contentIndex] = nil;
    end

    function RecyclableFrameMixin:UpdateView()
        local viewSize = self:GetViewSize();
        local fromOffset = self:GetVerticalScroll(); --self:GetScrollTarget();
        local toOffset = fromOffset + viewSize;

        for contentIndex, data in ipairs(self.content) do
            if (data.offsetY <= fromOffset and data.endingOffsetY >= fromOffset) or (data.offsetY >= fromOffset and data.endingOffsetY <= toOffset) or (data.offsetY <= toOffset and data.endingOffsetY >= toOffset) then
                --In range
                if not self.contentIndexObject[contentIndex] then
                    self.contentIndexObject[contentIndex] = self:AcquireAndSetData(data);
                end
            else
                --Outside range
                if self.contentIndexObject[contentIndex] then
                    self:RecycleObject(contentIndex);
                end
            end
        end
    end

    function RecyclableFrameMixin:DebugGetCount()
        local active = 0;
        local unused = 0;

        for contentIndex, obj in pairs(self.contentIndexObject) do
            active = active + 1;
        end

        for type, bin in pairs(self.bins) do
            for _, obj in pairs(bin) do
                unused = unused + 1;
            end
        end

        print("Active:", active, " Unused:", unused)
    end

    --Overridden by Owner
    function RecyclableFrameMixin:SetObjectData(object, data)
        --Override
        --Return object
    end

    function RecyclableFrameMixin:GetDataRequiredObjectType(data)
        --Override
    end


    local function InitRecyclableScrollFrame(scrollFrame)
        API.Mixin(scrollFrame, RecyclableFrameMixin);
        scrollFrame.isRecyclable = true;
    end
    addon.InitRecyclableScrollFrame = InitRecyclableScrollFrame;
end
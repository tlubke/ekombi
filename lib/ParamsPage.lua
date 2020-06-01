local fileselect = require 'fileselect'
local textentry = require 'textentry'

local pp = {
    params = nil,
    pos = 0,
    oldpos = 0,
    group = false,
    alt = false,
    fine = false,
    visible = false,
    triggered = {},
}

local page = nil

local function build_page()
    page = {}
    if pp.params == nil then
        page = nil
        return
    end
    local i = 1
    repeat
        if pp.params:visible(i) then table.insert(page, i) end
        if pp.params:t(i) == pp.params.tGROUP then
            i = i + pp.params:get(i) + 1
        else i = i + 1 end
    until i > pp.params.count
end

local function build_sub(sub)
    page = {}
    if pp.params == nil then
        page = nil
        return
    end
    for i = 1,pp.params:get(sub) do
        if pp.params:visible(i + sub) then
            table.insert(page, i + sub)
        end
    end
end

local function newfile(file)
    if file ~= "cancel" then
        pp.params:set(page[pp.pos+1],file)
        pp.redraw()
    end

end

local function newtext(txt)
    print("SET TEXT: "..txt)
    if txt ~= "cancel" then
        pp.params:set(page[pp.pos+1],txt)
        pp.redraw()
    end
end

local function reset()
    page = nil
    pp.pos = 0
    pp.oldpos = 0
    pp.group = false
    pp.alt = false
    pp.fine = false
    pp.visible = false
    pp.triggered = {}
end

function pp.open()
    pp.visible = true
    pp.opened()
end

function pp.close()
    pp.visible = false
    pp.closed()
end

-- user definable callbacks
pp.opened = function() end
pp.closed = function() end

pp.set_params = function(paramset)
    reset()
    pp.params = paramset
    build_page()
end

pp.key = function(n,z)
    if n==1 and z==1 then
        pp.alt = true
    elseif n==1 and z==0 then
        pp.alt = false
    end
    -- EDIT
    if n==2 and z==1 then
        if pp.group==true then
            pp.group = false
            build_page()
            pp.pos = pp.oldpos
        else
            pp.close()
            return
        end
    elseif n==3 and z==1 then
        local i = page[pp.pos+1]
        local t = pp.params:t(i)
        if t == pp.params.tGROUP then
            build_sub(i)
            pp.group = true
            pp.groupname = pp.params:string(i)
            pp.oldpos = pp.pos
            pp.pos = 0
        elseif t == pp.params.tSEPARATOR then
            local n = pp.pos+1
            repeat
                n = n+1
                if n > #page then n = 1 end
            until pp.params:t(page[n]) == pp.params.tSEPARATOR
            pp.pos = n-1
        elseif t == pp.params.tFILE then
            fileselect.enter(_path.dust, newfile)
        elseif t == pp.params.tTEXT then
            textentry.enter(newtext, pp.params:get(i), "PARAM: "..pp.params:get_name(i))
        elseif t == pp.params.tTRIGGER then
            pp.params:set(i)
            pp.triggered[i] = 2
        end
        pp.fine = true
    elseif n==3 and z==0 then
        pp.fine = false
    end
end

pp.enc = function(n,d)
    -- normal scroll
    if n==2 and pp.alt==false then
        local prev = pp.pos
        pp.pos = util.clamp(pp.pos + d, 0, #page - 1)
        -- jump section
    elseif n==2 and pp.alt==true then
        d = d>0 and 1 or -1
        local i = pp.pos+1
        repeat
            i = i+d
            if i > #page then i = 1 end
            if i < 1 then i = #page end
        until pp.params:t(page[i]) == pp.params.tSEPARATOR or i==1
        pp.pos = i-1
        -- adjust value
    elseif n==3 and pp.params.count > 0 then
        local dx = pp.fine and (d/20) or d
        pp.params:delta(page[pp.pos+1],dx)
    end
end

pp.scroll = function(n)
    pp.enc(2, n)
end

pp.redraw = function()
    if page == nil then return end
    screen.clear()
    if pp.pos == 0 then
        local n = pp.params.name
        if pp.group then n = n .. " / " .. pp.groupname end
        screen.level(15)
        screen.move(0,10)
        screen.text(n)
    end
    for i=1,6 do
        if (i > 2 - pp.pos) and (i < #page - pp.pos + 3) then
            if i==3 then screen.level(15) else screen.level(4) end
            local p = page[i+pp.pos-2]
            local t = pp.params:t(p)
            if t == pp.params.tSEPARATOR then
                screen.move(0,10*i+2.5)
                screen.line_rel(127,0)
                screen.stroke()
                screen.move(63,10*i)
                screen.text_center(pp.params:get_name(p))
            elseif t == pp.params.tGROUP then
                screen.move(0,10*i)
                screen.text(pp.params:get_name(p) .. " >")
            else
                screen.move(0,10*i)
                screen.text(pp.params:get_name(p))
                screen.move(127,10*i)
                if t ==  pp.params.tTRIGGER then
                    if pp.triggered[p] and pp.triggered[p] > 0 then
                        screen.rect(124, 10 * i - 4, 3, 3)
                        screen.fill()
                    end
                else
                    screen.text_right(pp.params:string(p))
                end
            end
        end
    end
    screen.update()
end

return pp
--- Clipboard.internal.paste
--- 剪贴板操作层：写回系统剪贴板、触发粘贴。
--- 职责：选中条目后如何把内容放回剪贴板并粘贴到前台应用。
local paste = {}

local logger = hs.logger.new("Clipboard.paste", "info")

--- 把条目写回系统剪贴板
--- @param entry 条目 {dbid, text, created}；text 可能是普通文本或图片的 data:image data URI
--- @return boolean 是否成功
function paste.writeBack(entry)
    if not entry then return false end
    local text = entry.text or ""
    -- 是图片 data URI：还原成 image 对象写入剪贴板；否则写入原文本
    if text:sub(1, 11) == "data:image/" then
        local img
        pcall(function() img = hs.image.imageFromURL(text) end)
        if img then
            local ok = pcall(function()
                hs.pasteboard.clearContents()
                hs.pasteboard.writeObjects({ img })
            end)
            if not ok then logger.e("写图片回剪贴板失败"); return false end
            return true
        end
    end
    hs.pasteboard.setContents(text)
    return true
end

--- 触发一次真实粘贴（Cmd+V 到前台应用）
function paste.doPaste()
    hs.timer.doAfter(0.08, function()
        hs.eventtap.keyStroke({ "cmd" }, "V")
    end)
end

--- 完整动作链：写回 + 粘贴
function paste.pasteAndFocus(entry)
    if paste.writeBack(entry) then
        paste.doPaste()
    end
end

return paste

local M = {}

M.current_placement = nil
M.current_url = nil
M.preview_win = nil
M.preview_buf = nil
M.request_id = 0
local timer = vim.uv.new_timer()

local function hide_loading_text()
  pcall(vim.api.nvim_set_hl, 0, "SnacksImageLoading", { link = "NonText", default = true })
  pcall(vim.api.nvim_set_hl, 0, "SnacksImageSpinner", { link = "NonText", default = true })
end

function M.close_preview()
  timer:stop()
  M.request_id = M.request_id + 1
  if M.current_placement then
    local p = M.current_placement
    M.current_placement = nil
    pcall(function() p:close() end)
  end
  if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
    pcall(vim.api.nvim_win_close, M.preview_win, true)
  end
  M.preview_win = nil
  M.current_url = nil
end

function M.handle_hover(url, yazi_win_id)
  if not _G.Snacks or not _G.Snacks.image then return end

  if not url or url == "" or not Snacks.image.supports(url) then
    M.close_preview()
    return
  end

  if M.current_url == url then return end
  M.current_url = url
  
  timer:stop()
  M.request_id = M.request_id + 1
  local rid = M.request_id

  timer:start(150, 0, vim.schedule_wrap(function()
    if rid ~= M.request_id or M.current_url ~= url then return end
    if not vim.api.nvim_win_is_valid(yazi_win_id) then
      M.close_preview()
      return
    end

    hide_loading_text()

    -- [Bug Fix] 매 세션마다 yazi 버퍼에 대한 종료 감지기를 등록해야 함
    local yazi_buf = vim.api.nvim_win_get_buf(yazi_win_id)
    if not vim.b[yazi_buf].yazi_snacks_attached then
      vim.b[yazi_buf].yazi_snacks_attached = true
      vim.api.nvim_create_autocmd({ "BufWipeout", "WinClosed", "VimLeavePre" }, {
        buffer = yazi_buf,
        callback = function() M.close_preview() end,
        once = true,
      })
    end

    if not M.preview_buf or not vim.api.nvim_buf_is_valid(M.preview_buf) then
      M.preview_buf = vim.api.nvim_create_buf(false, true)
      pcall(vim.api.nvim_set_option_value, "bufhidden", "hide", { buf = M.preview_buf })
    end
    
    local buf = M.preview_buf
    pcall(function()
      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      local lines = {}
      for i = 1, 100 do table.insert(lines, "") end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end)

    local yazi_width = vim.api.nvim_win_get_width(yazi_win_id)
    local yazi_height = vim.api.nvim_win_get_height(yazi_win_id)

    local start_col = math.floor(yazi_width * 0.5)
    local preview_width = yazi_width - start_col
    local preview_row = 2 
    local preview_height = math.max(1, yazi_height - preview_row)

    local win_opts = {
      style = "minimal",
      relative = "win",
      win = yazi_win_id,
      row = preview_row,
      col = start_col,
      width = math.max(1, preview_width),
      height = preview_height,
      zindex = 150,
      focusable = false,
      noautocmd = true,
      border = "none",
    }

    if M.preview_win and vim.api.nvim_win_is_valid(M.preview_win) then
      pcall(vim.api.nvim_win_set_config, M.preview_win, win_opts)
    else
      M.preview_win = vim.api.nvim_open_win(buf, false, win_opts)
      pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = M.preview_win })
      pcall(vim.api.nvim_set_option_value, "wrap", false, { win = M.preview_win })
    end

    if M.current_placement then
      local p = M.current_placement
      M.current_placement = nil
      pcall(function() p:close() end)
    end

    vim.defer_fn(function()
      if rid ~= M.request_id or M.current_url ~= url then return end
      
      local ok, placement = pcall(function()
        return Snacks.image.placement.new(buf, url, {
          pos = { 1, 0 },
          width = preview_width + 1,
          height = preview_height + 1,
          max_width = preview_width + 1,
          max_height = preview_height + 1,
          inline = true,
        })
      end)

      if ok and rid == M.request_id then
        M.current_placement = placement
        
        if placement.img then
          local original_on_ready = placement.img.on_ready
          placement.img.on_ready = function(self)
            if self.info then 
                self.info.dpi = { width = 96, height = 96 }
            end
            if original_on_ready then original_on_ready(self) end
            
            vim.schedule(function()
              if placement then placement:update() end
            end)
          end
          if placement.img.info then 
              placement.img.info.dpi = { width = 96, height = 96 }
              placement:update()
          end
        end
        
      elseif ok then
        pcall(function() placement:close() end)
      end
    end, 10)
  end))
end

return M
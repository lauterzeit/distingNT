-- Tintinnalogia
--[[
Traditional English change-ringing sequencer.
]]
-- Copyright (c) 2025 Nick Yablon
-- Inputs:  In1 = Clock, In2 = Start/Reset
-- Outputs: Out1-8 = Bell triggers 1-8

-- Pre-allocate buffers to avoid garbage collection
local temp_swaps = {}  -- Reusable buffer for apply_random
local temp_pairs = {}  -- Reusable buffer for apply_random_variation
local temp_new = {}    -- Reusable buffer for apply_random_variation

-- Helper: apply Plain Hunt swap rules
local function apply_plain_hunt(bells, change_num, num_bells, covering_tenor)
  local max_pos = num_bells or #bells
  
  -- If covering tenor is on, only work with bells 1 to N-1
  if covering_tenor then
    max_pos = max_pos - 1
  end
  
  if change_num % 2 == 1 then
    -- Odd rows: swap pairs 1-2, 3-4, 5-6, 7-8, etc
    for i = 1, max_pos - 1, 2 do
      bells[i], bells[i+1] = bells[i+1], bells[i]
    end
  else
    -- Even rows: swap pairs 2-3, 4-5, 6-7, etc (middle pairs only)
    for i = 2, max_pos - 1, 2 do
      bells[i], bells[i+1] = bells[i+1], bells[i]
    end
  end
end

-- Helper: apply Grandsire place notation
-- Grandsire works on odd numbers of bells (3, 5, 7)
-- Pattern: 3, 1.N.1.N.1... where N is the number of bells
local function apply_grandsire(bells, change_num, num_bells, covering_tenor)
  local max_pos = num_bells or #bells
  
  -- If covering tenor is on, only work with bells 1 to N-1
  -- The covering tenor (highest bell) stays fixed at position N
  if covering_tenor then
    max_pos = max_pos - 1
  end
  
  -- Grandsire only works on odd numbers
  -- If we have an even number, reduce by 1 to get odd
  -- (When covering tenor is on, this may mean fewer bells change)
  if max_pos % 2 == 0 then
    max_pos = max_pos - 1
  end
  
  -- change_num starts at 1 (first row after rounds)
  -- Pattern is: 3, 1, N, 1, N, 1, N...
  
  if change_num == 1 then
    -- First change: "3" (make 3rds place)
    -- Position 3 stays, swap pairs 1-2 and 4-5, 6-7, etc
    bells[1], bells[2] = bells[2], bells[1]  -- Swap 1-2
    for i = 4, max_pos - 1, 2 do
      bells[i], bells[i+1] = bells[i+1], bells[i]
    end
  else
    -- After first change, alternate between "1" and "N"
    -- change_num 2,4,6,8... → "1" (make 1st place)
    -- change_num 3,5,7,9... → "N" (make Nth place)
    local is_even = (change_num % 2 == 0)
    
    if is_even then
      -- "1" - make 1st place: position 1 stays, swap pairs 2-3, 4-5, etc
      for i = 2, max_pos - 1, 2 do
        bells[i], bells[i+1] = bells[i+1], bells[i]
      end
    else
      -- "N" - make Nth place: position N stays, swap pairs 1-2, 3-4, etc
      for i = 1, max_pos - 2, 2 do
        bells[i], bells[i+1] = bells[i+1], bells[i]
      end
    end
  end
end

-- Helper: apply Plain Bob place notation
-- Plain Bob works on even numbers of bells (4, 6, 8)
-- Place notation: -1N-1N-1N-1N-1N-12 (for N bells)
-- Pattern alternates between "cross all pairs" (-) and "make places" (1N or 12)
local function apply_plain_bob(bells, change_num, num_bells, covering_tenor)
  local max_pos = num_bells or #bells
  
  -- If covering tenor is on, only work with bells 1 to N-1
  -- The covering tenor (highest bell) stays fixed at position N
  if covering_tenor then
    max_pos = max_pos - 1
  end
  
  -- Plain Bob only works on even numbers
  -- If we have an odd number, reduce by 1 to get even
  -- (When covering tenor is on, this may mean fewer bells change)
  if max_pos % 2 == 1 then
    max_pos = max_pos - 1
  end
  
  -- Calculate position in the lead (12 changes per lead for Plain Bob: 6 pairs of -/1N)
  -- Pattern: -1N-1N-1N-1N-1N-12
  local lead_pos = ((change_num - 1) % 12) + 1
  
  if lead_pos % 2 == 1 and lead_pos < 11 then
    -- Odd positions (1, 3, 5, 7, 9): "-" = cross all pairs
    -- Swap all adjacent pairs: 1-2, 3-4, 5-6, 7-8, etc
    for i = 1, max_pos - 1, 2 do
      bells[i], bells[i+1] = bells[i+1], bells[i]
    end
  elseif lead_pos == 11 then
    -- Position 11: "-" before the lead end
    -- Swap all adjacent pairs
    for i = 1, max_pos - 1, 2 do
      bells[i], bells[i+1] = bells[i+1], bells[i]
    end
  elseif lead_pos == 12 then
    -- Position 12: Lead end "12" - make 1st and 2nd place
    -- Positions 1 and 2 stay, swap pairs 3-4, 5-6, 7-8, etc
    for i = 3, max_pos - 1, 2 do
      bells[i], bells[i+1] = bells[i+1], bells[i]
    end
  else
    -- Even positions (2, 4, 6, 8, 10): "1N" - make 1st and Nth place
    -- Position 1 stays, position max_pos stays, swap pairs 2-3, 4-5, 6-7, etc
    for i = 2, max_pos - 2, 2 do
      bells[i], bells[i+1] = bells[i+1], bells[i]
    end
  end
end

-- Helper: apply random transition
-- Randomly selects a valid swap from adjacent pairs
-- Ensures no consecutive identical swaps by tracking last swap
local function apply_random(bells, change_num, num_bells, covering_tenor, last_swap)
  local max_pos = num_bells or #bells
  
  -- If covering tenor is on, only work with bells 1 to N-1
  if covering_tenor then
    max_pos = max_pos - 1
  end
  
  -- Build list of possible swaps (reuse pre-allocated buffer)
  local count = 0
  for i = 1, max_pos - 1 do
    -- Don't include the last swap to avoid consecutive repeats
    if i ~= last_swap then
      count = count + 1
      temp_swaps[count] = i
    end
  end
  
  -- If all swaps were filtered out (edge case), allow any swap
  if count == 0 then
    for i = 1, max_pos - 1 do
      count = count + 1
      temp_swaps[count] = i
    end
  end
  
  -- Randomly select a swap
  local swap_index = math.random(1, count)
  local selected_swap = temp_swaps[swap_index]
  
  -- Perform the swap
  bells[selected_swap], bells[selected_swap + 1] = bells[selected_swap + 1], bells[selected_swap]
  
  -- Return the swap position so it can be tracked
  return selected_swap
end

-- Helper: calculate how many bells are actually changing in the method
-- (Some methods reduce bell count; covering tenor also reduces it)
local function get_active_bells(num_bells, method, covering_tenor)
  local active = num_bells
  
  -- Adjust for covering tenor
  if covering_tenor then
    active = active - 1
  end
  
  -- Adjust for method requirements
  if method == 2 then
    -- Grandsire needs odd - reduce if even
    if active % 2 == 0 then
      active = active - 1
    end
  elseif method == 3 then
    -- Plain Bob needs even - reduce if odd
    if active % 2 == 1 then
      active = active - 1
    end
  end
  
  return active
end

-- Helper: calculate extent length based on method and number of bells
local function get_extent_length(method, num_bells, covering_tenor)
  -- If covering tenor is on, calculate extent for N-1 bells
  local actual_bells = num_bells
  if covering_tenor then
    actual_bells = actual_bells - 1
  end
  
  if method == 1 then
    -- Plain Hunt: always 2*N rows
    return actual_bells * 2
  elseif method == 2 then
    -- Grandsire: plain course length varies by number of bells
    -- If even number, reduce by 1 (Grandsire only works on odd)
    if actual_bells % 2 == 0 then
      actual_bells = actual_bells - 1
    end
    
    -- The full extent would be factorial(N), but a plain course is shorter
    -- Plain course lengths: 3 bells = 6, 5 bells = 30, 7 bells = 70
    if actual_bells == 3 then
      return 6
    elseif actual_bells == 5 then
      return 30
    elseif actual_bells == 7 then
      return 70
    else
      return actual_bells * 2  -- Fallback
    end
  elseif method == 3 then
    -- Plain Bob: plain course length varies by number of bells
    -- If odd number, reduce by 1 (Plain Bob only works on even)
    if actual_bells % 2 == 1 then
      actual_bells = actual_bells - 1
    end
    
    -- Plain course lengths (until rounds): 4 bells = 24, 6 bells = 60, 8 bells = 56
    if actual_bells == 4 then
      return 24
    elseif actual_bells == 6 then
      return 60
    elseif actual_bells == 8 then
      return 56
    else
      return actual_bells * 6  -- Fallback (6 changes per lead)
    end
  elseif method == 4 then
    -- Random: aims for full extent (all permutations)
    -- Calculate factorial: 3! = 6, 4! = 24, 5! = 120, 6! = 720, 7! = 5040, 8! = 40320
    local factorial = 1
    for i = 2, actual_bells do
      factorial = factorial * i
    end
    return factorial
  end
  return actual_bells * 2  -- Default fallback
end

-- Helper: apply random variation (swap 1-2 random adjacent pairs)
local function apply_random_variation(bells, num_bells)
  -- Decide how many pairs to swap (1 or 2)
  local num_swaps = math.random(1, 2)
  
  -- Create a list of available adjacent pairs (reuse buffer)
  local pair_count = 0
  for i = 1, num_bells - 1 do
    pair_count = pair_count + 1
    temp_pairs[pair_count] = i
  end
  
  -- Randomly select and swap pairs
  for swap_count = 1, num_swaps do
    if pair_count == 0 then break end
    
    -- Pick a random pair from available
    local pair_index = math.random(1, pair_count)
    local pos = temp_pairs[pair_index]
    
    -- Swap the bells at positions pos and pos+1
    bells[pos], bells[pos+1] = bells[pos+1], bells[pos]
    
    -- Remove this pair and adjacent pairs from available list
    -- (to avoid swapping overlapping pairs like 1-2 and 2-3)
    local new_count = 0
    for i = 1, pair_count do
      local p = temp_pairs[i]
      if math.abs(p - pos) > 1 then
        new_count = new_count + 1
        temp_pairs[new_count] = p
      end
    end
    pair_count = new_count
  end
end

return {
  name   = 'Tintinnalogia',
  author = 'Nick Yablon',

  init = function(self)
    -- Bell positions (which bell number is in each position)
    -- Pre-allocate for max 8 bells to avoid reallocation
    self.bells = {1, 2, 3, 4, 5, 6, 7, 8}
    
    -- Sequencer state
    self.current_pos = 1    -- Current position in row (1-8)
    self.row_num = 0        -- Current row number (0 = rounds/starting)
    self.changing = false   -- Whether changes are active
    self.extent_complete = false
    self.row_repeat_count = 0  -- How many times current row has been played
    self.call_pending = false  -- Call Change mode: advance queued for end of row
    self.pause_next_clock = false  -- Handstroke pause: skip next clock pulse
    self.is_handstroke = true  -- Track handstroke (true) vs backstroke (false)
    self.variation_pending = false  -- Variation input: random alteration queued
    self.last_random_swap = nil  -- Track last swap for random method (avoid consecutive repeats)
    
    -- Trigger timing and velocity
    self.trigger_time = {}
    self.trigger_velocity = {}
    for i = 1, 9 do  -- 8 bells + pause
      self.trigger_time[i] = 0
      self.trigger_velocity[i] = 3.0  -- Default to 3V (unaccented)
    end
    
    -- Pre-allocate outputs array to avoid garbage collection in step()
    self.outputs = {}
    for i = 1, 9 do
      self.outputs[i] = 0.0
    end
    
    -- Pre-allocate empty table for pause returns
    self.empty_return = {}
    
    -- Pre-allocate row_history structure with reusable bell arrays
    self.row_history = {
      [1] = { bells = {}, row_num = 0 },
      [2] = { bells = {}, row_num = 0 }
    }
    for i = 1, 8 do
      self.row_history[1].bells[i] = 0
      self.row_history[2].bells[i] = 0
    end
    
    return {
      inputs      = { kGate, kGate, kGate, kGate },
      inputNames  = { 'Clock', 'Changes', 'Rounds', 'Variation' },
      
      outputs     = { kGate, kGate, kGate, kGate, kGate, kGate, kGate, kGate, kGate },
      outputNames = { 'Bell 1', 'Bell 2', 'Bell 3', 'Bell 4', 
                      'Bell 5', 'Bell 6', 'Bell 7', 'Bell 8', 'Pause' },
      
      parameters  = {
        {'Style', {'Method', 'Call Change'}, 1},
        {'Method', {'Plain Hunt', 'Grandsire', 'Plain Bob', 'Random'}, 1},
        {'Number of bells', 3, 8, 8},
        {'Covering tenor', {'Off', 'On'}, 1},
        {'Run mode', {'Once', 'Repeat'}, 1},
        {'Row repeats', 1, 8, 1},
        {'Handstroke pause', {'Off', 'On'}, 1},
        {'Accents', {'None', 'Treble', 'Lead'}, 1},
        {'Changes', {'Off', 'On'}, 2},
        {'Pause gate', {'Off', 'On'}, 1},
      }
    }
  end,

  step = function(self, dt, inputs)
    -- Single loop: decay trigger times AND update outputs
    for i = 1, 9 do
      if self.trigger_time[i] > 0 then
        self.trigger_time[i] = self.trigger_time[i] - dt
        if self.trigger_time[i] < 0 then
          self.trigger_time[i] = 0
        end
      end
      self.outputs[i] = (self.trigger_time[i] > 0) and self.trigger_velocity[i] or 0.0
    end
    
    return self.outputs
  end,

  gate = function(self, input, rising)
    if not rising then return end
    
    -- Input 4: Variation (queue random alteration)
    if input == 4 then
      self.variation_pending = true
      return
    end
    
    -- Input 3: Rounds (reset to row 0)
    if input == 3 then
      local num_bells = (self.parameters and self.parameters[3]) or 8
      -- Reuse existing bells array, clear all 8 positions
      for i = 1, 8 do
        if i <= num_bells then
          self.bells[i] = i
        else
          self.bells[i] = 0  -- Clear unused positions
        end
      end
      self.current_pos = 1
      self.row_num = 0
      self.changing = false
      self.extent_complete = false
      self.row_repeat_count = 0
      self.call_pending = false
      self.variation_pending = false
      self.pause_next_clock = false
      self.is_handstroke = true
      -- Clear row_history values
      self.row_history[1].row_num = 0
      self.row_history[2].row_num = 0
      self.last_random_swap = nil
      return
    end
    
    -- Input 2: Changes (behavior depends on Style parameter)
    if input == 2 then
      -- Get style parameter (1 = Method, 2 = Call Change)
      local style = (self.parameters and self.parameters[1]) or 1
      
      if style == 1 then
        -- Method mode: toggle the Changes parameter (parameter 9)
        -- This ensures parameter and gate input stay in sync
        local current_value = (self.parameters and self.parameters[9]) or 1
        local new_value = (current_value == 1) and 2 or 1  -- Toggle between Off and On
        self.parameters[9] = new_value
        
        -- Update changing state to match
        self.changing = (new_value == 2)
        
        -- Clear extent_complete flag when turning Changes back on
        if new_value == 2 then
          self.extent_complete = false
        end
      else
        -- Call Change mode: queue advance for end of current row
        self.call_pending = true
      end
      return
    end
    
    -- Input 1: Clock (ring current bell and advance)
    if input == 1 then
      -- In Method mode, sync changing state with Changes parameter before processing
      local style = (self.parameters and self.parameters[1]) or 1
      if style == 1 then
        local changes_param = (self.parameters and self.parameters[9]) or 1
        self.changing = (changes_param == 2)
      end
      
      -- Check if this clock should be paused (consume it without triggering)
      if self.pause_next_clock then
        self.pause_next_clock = false
        
        -- Fire pause trigger on output 9 if enabled (parameter 10: 1=Off, 2=On)
        local pause_enabled = (self.parameters and self.parameters[10]) or 1
        if pause_enabled == 2 then
          self.trigger_time[9] = 0.010  -- 10ms trigger pulse
          self.trigger_velocity[9] = 5.0
        end
        
        return self.empty_return  -- Use pre-allocated empty table
      end
      
      -- Fire trigger for current bell in sequence
      local num_bells = (self.parameters and self.parameters[3]) or 8
      
      local bell_num = self.bells[self.current_pos]
      if not bell_num then
        -- Failsafe: if bells array is malformed, reset (reuse existing array)
        for i = 1, num_bells do
          self.bells[i] = i
        end
        bell_num = self.bells[self.current_pos]
      end
      
      -- Calculate velocity based on Accents parameter (parameter 8)
      local accent_mode = (self.parameters and self.parameters[8]) or 1
      local velocity = 3.0  -- Default unaccented velocity (3V)
      
      if accent_mode == 2 then
        -- Treble mode: accent bell 1
        velocity = (bell_num == 1) and 5.0 or 3.0
      elseif accent_mode == 3 then
        -- Lead mode: accent bell in position 1
        velocity = (self.current_pos == 1) and 5.0 or 3.0
      end
      -- Mode 1 (None): all bells at 3.0V (already set)
      
      self.trigger_time[bell_num] = 0.010  -- 10ms trigger pulse
      self.trigger_velocity[bell_num] = velocity
      
      -- Get number of bells from parameter
      local num_bells = (self.parameters and self.parameters[3]) or 8
      
      -- Determine how many bells are actively changing (for handstroke pause check)
      local method = (self.parameters and self.parameters[2]) or 1
      local covering_tenor = ((self.parameters and self.parameters[4]) or 1) == 2
      local active_bells = get_active_bells(num_bells, method, covering_tenor)
      
      -- Check if we just rang the last bell and should set pause for next clock
      -- If covering tenor is on, pause after covering bell; otherwise after last active bell
      local last_bell_pos = active_bells
      if covering_tenor then
        last_bell_pos = active_bells + 1  -- After covering bell
      end
      
      if self.current_pos == last_bell_pos then
        local handstroke_pause = (self.parameters and self.parameters[7]) or 1
        if handstroke_pause == 2 and not self.is_handstroke then
          self.pause_next_clock = true
        end
      end
      
      -- Advance position
      self.current_pos = self.current_pos + 1
      
      -- Determine when to end the row
      -- If covering tenor is on, ring one more bell after active_bells
      local covering_tenor = ((self.parameters and self.parameters[4]) or 1) == 2
      local row_length = active_bells
      if covering_tenor then
        row_length = active_bells + 1  -- Include covering bell at end
      end
      
      -- End of row - advance to next change if changing is active
      if self.current_pos > row_length then
        self.current_pos = 1
        
        -- Get style parameter (1 = Method, 2 = Call Change)
        local style = (self.parameters and self.parameters[1]) or 1
        
        if style == 1 then
          -- METHOD MODE
          -- Get row repeats parameter (default 1 if not set)
          local row_repeats = (self.parameters and self.parameters[6]) or 1
          
          -- Increment repeat counter
          self.row_repeat_count = self.row_repeat_count + 1
          
          -- Check if we've completed all repeats of this row
          if self.row_repeat_count >= row_repeats then
            -- Reset repeat counter for next row
            self.row_repeat_count = 0
            
            -- Only apply changes if changing is active and not complete
            if self.changing and not self.extent_complete then
              -- Shift history: [2] <- [1], [1] <- current
              -- Swap the row_history entries to avoid allocation
              local temp = self.row_history[2]
              self.row_history[2] = self.row_history[1]
              self.row_history[1] = temp
              
              -- Copy current bells into history[1] (reusing existing array)
              self.row_history[1].row_num = self.row_num
              for i = 1, num_bells do
                self.row_history[1].bells[i] = self.bells[i]
              end
              
              self.row_num = self.row_num + 1
              
              -- Check for extent completion
              local method = (self.parameters and self.parameters[2]) or 1
              local covering_tenor = ((self.parameters and self.parameters[4]) or 1) == 2
              local extent_length = get_extent_length(method, num_bells, covering_tenor)
              if self.row_num >= extent_length then
                -- Get run mode parameter (1 = Once, 2 = Repeat)
                local run_mode = self.parameters and self.parameters[5] or 1
                
                if run_mode == 1 then
                  -- Once: return to rounds and stop changing (reuse array)
                  for i = 1, num_bells do
                    self.bells[i] = i
                  end
                  self.row_num = 0
                  self.changing = false
                  self.extent_complete = true
                  -- Also set the Changes parameter to Off so UI reflects stopped state
                  if self.parameters then
                    self.parameters[9] = 1  -- 1 = Off
                  end
                else
                  -- Repeat: reset row counter and continue (reuse array)
                  self.row_num = 0
                  for i = 1, num_bells do
                    self.bells[i] = i
                  end
                end
              else
                -- Check if variation is pending
                if self.variation_pending then
                  -- Apply random variation instead of normal method
                  apply_random_variation(self.bells, num_bells)
                  self.variation_pending = false
                else
                  -- Apply method transformation based on Method parameter
                  local method = (self.parameters and self.parameters[2]) or 1
                  local covering_tenor = ((self.parameters and self.parameters[4]) or 1) == 2
                  if method == 1 then
                    -- Plain Hunt
                    apply_plain_hunt(self.bells, self.row_num, num_bells, covering_tenor)
                  elseif method == 2 then
                    -- Grandsire
                    apply_grandsire(self.bells, self.row_num, num_bells, covering_tenor)
                  elseif method == 3 then
                    -- Plain Bob
                    apply_plain_bob(self.bells, self.row_num, num_bells, covering_tenor)
                  elseif method == 4 then
                    -- Random
                    self.last_random_swap = apply_random(self.bells, self.row_num, num_bells, covering_tenor, self.last_random_swap)
                  end
                end
              end
            end
          end
          
          -- Toggle handstroke/backstroke after each row completion
          self.is_handstroke = not self.is_handstroke
          
        else
          -- CALL CHANGE MODE
          -- Check if a call is pending
          if self.call_pending then
            self.call_pending = false
            
            -- Shift history: [2] <- [1], [1] <- current (swap to avoid allocation)
            local temp = self.row_history[2]
            self.row_history[2] = self.row_history[1]
            self.row_history[1] = temp
            
            -- Copy current bells into history[1] (reusing existing array)
            self.row_history[1].row_num = self.row_num
            for i = 1, num_bells do
              self.row_history[1].bells[i] = self.bells[i]
            end
            
            self.row_num = self.row_num + 1
            
            -- In Call Change mode, always cycle back to rounds after extent
            local method = (self.parameters and self.parameters[2]) or 1
            local covering_tenor = ((self.parameters and self.parameters[4]) or 1) == 2
            local extent_length = get_extent_length(method, num_bells, covering_tenor)
            if self.row_num >= extent_length then
              self.row_num = 0
              -- Reuse bells array instead of creating new one
              for i = 1, num_bells do
                self.bells[i] = i
              end
            else
              -- Check if variation is pending
              if self.variation_pending then
                -- Apply random variation instead of normal method
                apply_random_variation(self.bells, num_bells)
                self.variation_pending = false
              else
                -- Apply method transformation (method already declared above)
                local covering_tenor = ((self.parameters and self.parameters[4]) or 1) == 2
                if method == 1 then
                  -- Plain Hunt
                  apply_plain_hunt(self.bells, self.row_num, num_bells, covering_tenor)
                elseif method == 2 then
                  -- Grandsire
                  apply_grandsire(self.bells, self.row_num, num_bells, covering_tenor)
                elseif method == 3 then
                  -- Plain Bob
                  apply_plain_bob(self.bells, self.row_num, num_bells, covering_tenor)
                elseif method == 4 then
                  -- Random
                  self.last_random_swap = apply_random(self.bells, self.row_num, num_bells, covering_tenor, self.last_random_swap)
                end
              end
            end
          end
          
          -- Toggle handstroke/backstroke after each row completion
          self.is_handstroke = not self.is_handstroke
          -- If no call pending, just loop current row (do nothing)
        end
      end
    end
  end,

  parameterChanged = function(self, param)
    -- Parameter 2: Method - reset to rounds when method changes
    if param == 2 then
      local num_bells = self.parameters[3] or 8
      
      -- Reset to rounds with current bell count (reuse array, clear all 8 positions)
      for i = 1, 8 do
        if i <= num_bells then
          self.bells[i] = i
        else
          self.bells[i] = 0  -- Clear unused positions
        end
      end
      self.current_pos = 1
      self.row_num = 0
      self.changing = false
      self.extent_complete = false
      self.row_repeat_count = 0
      self.call_pending = false
      self.variation_pending = false
      self.pause_next_clock = false
      self.is_handstroke = true
      -- Clear row_history values
      self.row_history[1].row_num = 0
      self.row_history[2].row_num = 0
      return
    end
    
    -- Parameter 3: Number of bells - reset to rounds when bell count changes
    if param == 3 then
      local num_bells = self.parameters[3] or 8
      
      -- Reset to rounds with new bell count (reuse array, clear all 8 positions)
      for i = 1, 8 do
        if i <= num_bells then
          self.bells[i] = i
        else
          self.bells[i] = 0  -- Clear unused positions
        end
      end
      self.current_pos = 1
      self.row_num = 0
      self.changing = false
      self.extent_complete = false
      self.row_repeat_count = 0
      self.call_pending = false
      self.variation_pending = false
      self.pause_next_clock = false
      self.is_handstroke = true
      -- Clear row_history values
      self.row_history[1].row_num = 0
      self.row_history[2].row_num = 0
      self.last_random_swap = nil
      return
    end
    
    -- Parameter 9 is the Changes toggle
    if param == 9 then
      local changes_value = self.parameters[9] or 1
      -- Get style parameter (1 = Method, 2 = Call Change)
      local style = (self.parameters and self.parameters[1]) or 1
      
      if style == 1 then
        -- Method mode: parameter directly controls changing state
        -- 1 = Off, 2 = On
        self.changing = (changes_value == 2)
        
        -- Clear extent_complete flag when turning Changes back on
        if changes_value == 2 then
          self.extent_complete = false
        end
      else
        -- Call Change mode: each change to On triggers a call
        if changes_value == 2 then
          self.call_pending = true
        end
      end
    end
  end,

  draw = function(self)
    -- Get current number of bells from parameter
    local num_bells = (self.parameters and self.parameters[3]) or 8
    
    -- Helper: draw a row of bells with row number
    local function draw_bell_row(bells, y_pos, brightness, row_num, num_bells)
      local spacing = 30
      
      -- Center the bells on screen based on how many we have
      -- Screen is 256 pixels wide, reserve ~20 pixels on left for row number
      local bells_width = (num_bells - 1) * spacing  -- Width of all bells
      local x_start = ((256 - bells_width) / 2) - 5  -- Center, slight left adjustment
      
      -- Draw row number on the left with colon
      if row_num then
        drawText(2, y_pos, tostring(row_num) .. ":", brightness)
      end
      
      -- Draw bell numbers (only up to num_bells)
      local count = num_bells or #bells
      for i = 1, count do
        local x = x_start + (i - 1) * spacing
        drawText(x, y_pos, tostring(bells[i]), brightness)
      end
    end
    
    -- Helper: draw movement arrows from prev_row to curr_row
    local function draw_movement_arrows(prev_row, curr_row, y_prev, y_curr, brightness, num_bells)
      if not prev_row or not curr_row then return end
      
      local spacing = 30
      -- Center bells the same way as draw_bell_row
      local bells_width = (num_bells - 1) * spacing
      local x_offset = ((256 - bells_width) / 2) - 5
      
      local y_start = y_prev + 2   -- Start closer, directly below previous row
      local y_end = y_curr - 7     -- End above current row
      
      -- For each bell in current row, find where it was in previous row
      for curr_pos = 1, num_bells do
        local bell_num = curr_row[curr_pos]
        if not bell_num then break end  -- Safety check
        
        -- Find this bell's position in previous row
        local prev_pos = nil
        for i = 1, num_bells do
          if prev_row[i] == bell_num then
            prev_pos = i
            break
          end
        end
        
        -- Only draw arrow if bell moved
        if prev_pos and prev_pos ~= curr_pos then
          -- Start centered on source bell
          local x_from = x_offset + (prev_pos - 1) * spacing + 4
          
          -- End offset to the side of destination bell
          local x_to_center = x_offset + (curr_pos - 1) * spacing + 4
          local x_to
          if curr_pos > prev_pos then
            -- Moving right - offset significantly to the left of target
            x_to = x_to_center - 8
          else
            -- Moving left - offset to the right of target
            x_to = x_to_center + 2
          end
          
          -- Draw main line
          drawLine(x_from, y_start, x_to, y_end, brightness)
          
          -- Calculate arrow direction for arrowhead
          local dx = x_to - x_from
          local dy = y_end - y_start
          local len = math.sqrt(dx*dx + dy*dy)
          if len > 0 then
            -- Normalize direction
            dx = dx / len
            dy = dy / len
            
            -- Arrowhead size
            local arrow_len = 3
            local arrow_width = 2
            
            -- Perpendicular direction
            local px = -dy
            local py = dx
            
            -- Arrowhead points
            local base_x = x_to - dx * arrow_len
            local base_y = y_end - dy * arrow_len
            
            -- Draw arrowhead as two lines forming a V
            drawLine(x_to, y_end, 
                    base_x + px * arrow_width, base_y + py * arrow_width, 
                    brightness)
            drawLine(x_to, y_end, 
                    base_x - px * arrow_width, base_y - py * arrow_width, 
                    brightness)
          end
        end
      end
    end
    
    -- Calculate which rows to display (current + previous 2)
    if not self.row_history then
      self.row_history = {}
    end
    
    -- Draw three rows with more spacing
    local y_start = 17        -- Moved down 2 pixels from 15
    local row_spacing = 20    -- Increased from 16 to 20
    
    -- Row -2 (if exists)
    if self.row_history[2] then
      draw_bell_row(self.row_history[2].bells, y_start, 6, self.row_history[2].row_num, num_bells)
    end
    
    -- Draw arrows from row -2 to row -1 (if both exist)
    -- Skip if row -1 is rounds to avoid clutter
    if self.row_history[2] and self.row_history[1] and self.row_history[1].row_num > 0 then
      draw_movement_arrows(self.row_history[2].bells, self.row_history[1].bells, 
                          y_start, y_start + row_spacing, 6, num_bells)
    end
    
    -- Row -1 (if exists)
    if self.row_history[1] then
      draw_bell_row(self.row_history[1].bells, y_start + row_spacing, 10, self.row_history[1].row_num, num_bells)
    end
    
    -- Draw arrows from row -1 to current (if both exist)
    -- Skip arrows when current is rounds OR when previous is rounds
    if self.row_history[1] and self.row_num > 0 and self.row_history[1].row_num > 0 then
      draw_movement_arrows(self.row_history[1].bells, self.bells, 
                          y_start + row_spacing, y_start + row_spacing * 2, 10, num_bells)
    end
    
    -- Current row (brightest)
    local current_row_y = y_start + row_spacing * 2
    draw_bell_row(self.bells, current_row_y, 15, self.row_num, num_bells)
    
    -- Current position cursor (small dot below active bell on current row)
    -- Show which bell just rang (current_pos has already advanced, so go back one)
    local spacing = 30
    local bells_width = (num_bells - 1) * spacing
    local x_offset = ((256 - bells_width) / 2) - 5
    
    -- Calculate how many bells are actually ringing (includes covering bell if present)
    local method = (self.parameters and self.parameters[2]) or 1
    local covering_tenor = ((self.parameters and self.parameters[4]) or 1) == 2
    local active_bells = get_active_bells(num_bells, method, covering_tenor)
    
    local row_length = active_bells
    if covering_tenor then
      row_length = active_bells + 1  -- Include covering bell
    end
    
    -- Calculate the position that just rang
    local display_pos = self.current_pos - 1
    if display_pos < 1 then
      display_pos = row_length  -- Wrap around to last position (includes covering bell)
    end
    
    local cursor_x = x_offset + ((display_pos - 1) * spacing) + 3
    local cursor_y = current_row_y + 6
    drawRectangle(cursor_x - 1, cursor_y, cursor_x + 1, cursor_y + 1, 15)
  end,
}

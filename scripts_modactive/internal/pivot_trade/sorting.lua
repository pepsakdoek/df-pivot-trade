--@ module = true

local common = reqscript('internal/pivot_trade/common')
local trade = df.global.game.main_interface.trade


function get_entry_icon(data)
    if trade.goodflag[data.list_idx][data.item_idx].selected then
        return common.ALL_PEN
    end
end

function get_sort_level(sort_fn)
    if sort_fn == sort_by_name_desc or sort_fn == sort_by_name_asc then
        return 'name'
    elseif sort_fn == sort_by_grouped_desc or sort_fn == sort_by_grouped_asc then
        return 'grouped'
    elseif sort_fn == sort_by_subclass_desc or sort_fn == sort_by_subclass_asc then
        return 'subclass'
    elseif sort_fn == sort_by_class_desc or sort_fn == sort_by_class_asc then
        return 'class'
    elseif sort_fn == sort_by_value_desc or sort_fn == sort_by_value_asc then
        return 'value'
    elseif sort_fn == sort_by_count_desc or sort_fn == sort_by_count_asc then
        return 'count'
    elseif sort_fn == sort_by_status_desc or sort_fn == sort_by_status_asc then
        return 'status'
    end
    return 'unknown'
end

function sort_noop()
    -- this function is used as a marker and never actually gets called
    error('sort_noop should not be called')
end

local function sort_base(a, b)
    return a.data.desc < b.data.desc
end

function sort_by_name_desc(a, b)
    if a.search_key == b.search_key then
        return sort_base(a, b)
    end
    return a.search_key < b.search_key
end

function sort_by_name_asc(a, b)
    if a.search_key == b.search_key then
        return sort_base(a, b)
    end
    return a.search_key > b.search_key
end

function sort_by_value_desc(a, b)
    if a.data.value == b.data.value then
        return sort_by_name_desc(a, b)
    end
    return a.data.value > b.data.value
end

function sort_by_value_asc(a, b)
    if a.data.value == b.data.value then
        return sort_by_name_desc(a, b)
    end
    return a.data.value < b.data.value
end

function sort_by_status_desc(a, b)
    local a_selected = get_entry_icon(a.data)
    local b_selected = get_entry_icon(b.data)
    if a_selected == b_selected then
        return sort_by_value_desc(a, b)
    end
    return a_selected
end

function sort_by_status_asc(a, b)
    local a_selected = get_entry_icon(a.data)
    local b_selected = get_entry_icon(b.data)
    if a_selected == b_selected then
        return sort_by_value_desc(a, b)
    end
    return b_selected
end

function sort_by_class_desc(a, b)
    if a.data.class == b.data.class then return sort_by_value_desc(a, b) end
    return a.data.class < b.data.class
end

function sort_by_class_asc(a, b)
    if a.data.class == b.data.class then return sort_by_value_desc(a, b) end
    return a.data.class > b.data.class
end

function sort_by_subclass_desc(a, b)
    if a.data.subclass == b.data.subclass then return sort_by_value_desc(a, b) end
    return a.data.subclass < b.data.subclass
end

function sort_by_subclass_asc(a, b)
    if a.data.subclass == b.data.subclass then return sort_by_value_desc(a, b) end
    return a.data.subclass > b.data.subclass
end

function sort_by_count_desc(a, b)
    if a.data.quantity == b.data.quantity then
        return sort_by_value_desc(a, b)
    end
    return (a.data.quantity or 0) > (b.data.quantity or 0)
end

function sort_by_count_asc(a, b)
    if a.data.quantity == b.data.quantity then
        return sort_by_value_asc(a, b)
    end
    return (a.data.quantity or 0) < (b.data.quantity or 0)
end

function sort_by_grouped_desc(a, b)
    if a.data.grouped == b.data.grouped then return sort_by_value_desc(a, b) end
    return a.data.grouped < b.data.grouped
end

function sort_by_grouped_asc(a, b)
    if a.data.grouped == b.data.grouped then return sort_by_value_desc(a, b) end
    return a.data.grouped > b.data.grouped
end

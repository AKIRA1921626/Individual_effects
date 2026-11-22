-- ================================================================
-- グループ個別エフェクト 共通処理モジュール
-- ================================================================
local M = {}

-- まとめた文字群の中心点を計算する関数
local function get_group_center(start_num, end_num)
    local s = math.min(start_num, end_num)
    local e = math.max(start_num, end_num)
    local min_x, max_x = math.huge, -math.huge
    local min_y, max_y = math.huge, -math.huge
    local count = 0

    for i = s - 1, e - 1 do
        local ox = _G.gi_ox and _G.gi_ox[i]
        local oy = _G.gi_oy and _G.gi_oy[i]
        local w  = (_G.gi_w and _G.gi_w[i]) or 0
        local h  = (_G.gi_h and _G.gi_h[i]) or 0
        if ox and oy then
            count = count + 1
            local left   = ox - w / 2
            local right  = ox + w / 2
            local top    = oy - h / 2
            local bottom = oy + h / 2
            if left < min_x then min_x = left end
            if right > max_x then max_x = right end
            if top < min_y then min_y = top end
            if bottom > max_y then max_y = bottom end
        end
    end

    if count == 0 then
        return 0, 0
    end

    return (min_x + max_x) / 2, (min_y + max_y) / 2
end

-- 1つのグループ（A, B, C）のバッファ合成・エフェクトコールバック実行・キャッシュ保存
local function process_group(group_name, current_char, idx, start_raw, end_raw, s_norm, e_norm, full_w, full_h, pack, effect_callback)
    if current_char < e_norm then
        -- 【非終了文字の処理】
        obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
        obj.clearbuffer("tempbuffer")

        obj.draw(
            _G.gi_ox[idx], _G.gi_oy[idx], _G.gi_oz[idx],
            _G.gi_scale[idx], _G.gi_alpha[idx],
            _G.gi_rx[idx], _G.gi_ry[idx], _G.gi_rz[idx]
        )

        obj.copybuffer("cache:gi_" .. group_name .. "_" .. idx, "tempbuffer")

        obj.setoption("drawtarget", "framebuffer")
        obj.load("tempbuffer")
        obj.clearbuffer("object")

    elseif current_char == e_norm then
        -- 【終了文字の処理】
        obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
        obj.clearbuffer("tempbuffer")

        -- (1) 終了文字を描画
        obj.draw(
            _G.gi_ox[idx], _G.gi_oy[idx], _G.gi_oz[idx],
            _G.gi_scale[idx], _G.gi_alpha[idx],
            _G.gi_rx[idx], _G.gi_ry[idx], _G.gi_rz[idx]
        )

        -- (2) 開始文字 ～ 終了文字の1つ前 までのキャッシュを合成
        for i = s_norm - 1, e_norm - 2 do
            obj.copybuffer("object", "cache:gi_" .. group_name .. "_" .. i)
            obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
        end

        -- (3) フレームバッファに読み込み、中心点を移動
        obj.setoption("drawtarget", "framebuffer")
        obj.load("tempbuffer")

        local cx, cy = get_group_center(start_raw, end_raw)
        obj.cx = cx
        obj.cy = cy
        obj.ox = cx
        obj.oy = cy

        -- (4) 呼び出し元から渡されたグループ固有のエフェクト処理を実行
        if type(effect_callback) == "function" then
            effect_callback()
        end

        -- (5) pack == 2 の場合はエフェクト適用後画像をキャッシュして不可視化
        if pack == 2 then
            obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
            obj.clearbuffer("tempbuffer")
            obj.ox = 0; obj.oy = 0; obj.oz = 0; obj.rx = 0; obj.ry = 0; obj.rz = 0; obj.cx = 0; obj.cy = 0
            obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
            obj.copybuffer("cache:packed_group_" .. group_name, "tempbuffer")
            _G["gi_has_packed_" .. group_name] = true

            obj.setoption("drawtarget", "framebuffer")
            obj.clearbuffer("object")
        else
            obj.clearbuffer("tempbuffer")
        end
    end
end

-- メイン実行関数
-- config テーブルの内容:
--   startA, endA, effectA (関数)
--   startB, endB, effectB (関数)
--   startC, endC, effectC (関数)
--   pack (0: まとめない, 1: 範囲外の文字をまとめる, 2: すべての文字をまとめる)
function M.execute(config)
    -- ヘルパーモジュールの読み込みを試行
    local condition, AKIRA_helper = pcall(require, "AKIRA_aviutl2_helper")
    local AKIRA_h = condition and AKIRA_helper or nil
    if not condition then
        debug_print("AKIRA_aviutl2_helper.luaが同じフォルダに存在しません。")
    end

    -- 個別オブジェクトが有効かを確認
    local is_multi = obj.getoption("multi_object")
    if not is_multi then
        debug_print("個別オブジェクトが有効ではないため、「個別エフェクト」処理をスキップします。")
        return
    end

    -- グローバル変数の初期化 (index == 0 のときリセット)
    if obj.index == 0 then
        _G.gi_ox    = {}
        _G.gi_oy    = {}
        _G.gi_oz    = {}
        _G.gi_scale = {}
        _G.gi_alpha = {}
        _G.gi_rx    = {}
        _G.gi_ry    = {}
        _G.gi_rz    = {}
        _G.gi_has_packed_A = false
        _G.gi_has_packed_B = false
        _G.gi_has_packed_C = false
    end

    -- 現在の文字の位置・変形情報を保存
    local idx   = obj.index
    local last  = obj.num - 1
    local scale = obj.sx
    local alpha = obj.getvalue("alpha")

    _G.gi_ox[idx]    = obj.ox
    _G.gi_oy[idx]    = obj.oy
    _G.gi_oz[idx]    = obj.oz
    _G.gi_scale[idx] = scale
    _G.gi_alpha[idx] = alpha
    _G.gi_rx[idx]    = obj.rx
    _G.gi_ry[idx]    = obj.ry
    _G.gi_rz[idx]    = obj.rz

    -- グループ範囲の正規化
    local total_char = obj.num
    local startA = config.startA or 1
    local endA   = config.endA or 1
    local startB = config.startB or 1
    local endB   = config.endB or 1
    local startC = config.startC or 1
    local endC   = config.endC or 1

    local sA = math.min(startA, endA)
    local eA = math.min(math.max(startA, endA), total_char)
    local sB = math.min(startB, endB)
    local eB = math.min(math.max(startB, endB), total_char)
    local sC = math.min(startC, endC)
    local eC = math.min(math.max(startC, endC), total_char)

    local current_char = idx + 1

    local inA = (current_char >= sA and current_char <= eA)
    local inB = (current_char >= sB and current_char <= eB)
    local inC = (current_char >= sC and current_char <= eC)

    local pack = config.pack or 0
    local last_other_idx = -1
    if pack == 1 then
        for i = 0, obj.num - 1 do
            local c = i + 1
            local is_in_grp = (c >= sA and c <= eA) or (c >= sB and c <= eB) or (c >= sC and c <= eC)
            if not is_in_grp then
                last_other_idx = i
            end
        end
    end

    -- 合成バッファのサイズを取得
    local full_w = obj.screen_w
    local full_h = obj.screen_h
    if AKIRA_h then
        local tw, th = AKIRA_h.get_text_size()
        local lc     = AKIRA_h.line_break_confirmation()
        full_w = math.min(obj.screen_w, tw)
        full_h = math.min(obj.screen_h, th * lc)
    end

    -- 各グループまたはグループ外の分岐処理
    if inA then
        process_group("A", current_char, idx, startA, endA, sA, eA, full_w, full_h, pack, config.effectA)
    elseif inB then
        process_group("B", current_char, idx, startB, endB, sB, eB, full_w, full_h, pack, config.effectB)
    elseif inC then
        process_group("C", current_char, idx, startC, endC, sC, eC, full_w, full_h, pack, config.effectC)
    elseif idx <= last then
        if pack == 2 then
            obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
            obj.clearbuffer("tempbuffer")
            obj.draw(
                _G.gi_ox[idx], _G.gi_oy[idx], _G.gi_oz[idx],
                _G.gi_scale[idx], _G.gi_alpha[idx],
                _G.gi_rx[idx], _G.gi_ry[idx], _G.gi_rz[idx]
            )
            obj.copybuffer("cache:gi_other_" .. idx, "tempbuffer")
            obj.setoption("drawtarget", "framebuffer")
            obj.load("tempbuffer")
            obj.clearbuffer("object")

        elseif pack == 1 then
            if idx < last_other_idx then
                obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
                obj.clearbuffer("tempbuffer")
                obj.draw(
                    _G.gi_ox[idx], _G.gi_oy[idx], _G.gi_oz[idx],
                    _G.gi_scale[idx], _G.gi_alpha[idx],
                    _G.gi_rx[idx], _G.gi_ry[idx], _G.gi_rz[idx]
                )
                obj.copybuffer("cache:gi_other_" .. idx, "tempbuffer")
                obj.setoption("drawtarget", "framebuffer")
                obj.load("tempbuffer")
                obj.clearbuffer("object")
            else
                obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
                obj.clearbuffer("tempbuffer")
                for i = 0, idx - 1 do
                    local c = i + 1
                    local is_in_grp = (c >= sA and c <= eA) or (c >= sB and c <= eB) or (c >= sC and c <= eC)
                    if not is_in_grp then
                        obj.copybuffer("object", "cache:gi_other_" .. i)
                        obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                    end
                end
                obj.draw(
                    _G.gi_ox[idx], _G.gi_oy[idx], _G.gi_oz[idx],
                    _G.gi_scale[idx], _G.gi_alpha[idx],
                    _G.gi_rx[idx], _G.gi_ry[idx], _G.gi_rz[idx]
                )
                obj.setoption("drawtarget", "framebuffer")
                obj.load("tempbuffer")
                obj.clearbuffer("tempbuffer")
            end
        else
            obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
            obj.draw(
                _G.gi_ox[idx], _G.gi_oy[idx], _G.gi_oz[idx],
                _G.gi_scale[idx], _G.gi_alpha[idx],
                _G.gi_rx[idx], _G.gi_ry[idx], _G.gi_rz[idx]
            )
            obj.load("tempbuffer")
            obj.clearbuffer("tempbuffer")
        end
    else
        return
    end

    -- pack == 2: 最後の文字のタイミングで全グループ＋範囲外文字を1枚に合成
    if pack == 2 and idx == last then
        obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
        obj.clearbuffer("tempbuffer")

        for i = 0, obj.num - 1 do
            local c = i + 1
            local is_in_grp = (c >= sA and c <= eA) or (c >= sB and c <= eB) or (c >= sC and c <= eC)
            if not is_in_grp then
                if obj.copybuffer("object", "cache:gi_other_" .. i) then
                    obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                end
            end
        end

        if _G.gi_has_packed_A then
            if obj.copybuffer("object", "cache:packed_group_A") then
                obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
            end
        end

        if _G.gi_has_packed_B then
            if obj.copybuffer("object", "cache:packed_group_B") then
                obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
            end
        end

        if _G.gi_has_packed_C then
            if obj.copybuffer("object", "cache:packed_group_C") then
                obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
            end
        end

        obj.setoption("drawtarget", "framebuffer")
        obj.load("tempbuffer")
        obj.clearbuffer("tempbuffer")
    end
end

return M

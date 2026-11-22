-- ================================================================
-- グループ個別エフェクト追加 共通処理モジュール
-- 「@個別エフェクト.anm2」で指定されたグループ(A, B, C)に対し、
-- 追加でエフェクトを適用し、必要に応じて文字のまとめ(pack)を行う
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

-- 1つのグループ（A, B, C）に対する追加エフェクト実行・キャッシュ保存処理
local function process_add_group(group_name, current_char, idx, s_norm, e_norm, full_w, full_h, pack, effect_callback)
    if current_char < e_norm then
        -- 【非終了文字の処理】先行フィルタで不可視化されているため不可視を維持
        obj.setoption("drawtarget", "framebuffer")
        obj.clearbuffer("object")

    elseif current_char == e_norm then
        -- 【終了文字の処理】先行フィルタでグループ全文字が合体済みのオブジェクトが入っている
        local cx = _G["gi_cx_" .. group_name] or 0
        local cy = _G["gi_cy_" .. group_name] or 0
        obj.cx = cx
        obj.cy = cy
        obj.ox = cx
        obj.oy = cy

        -- 追加エフェクト処理を実行
        if type(effect_callback) == "function" then
            effect_callback()
        end

        -- pack == 2 の場合はエフェクト適用後画像をキャッシュして不可視化
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
            -- pack == 0 または 1 の場合はそのままフレームバッファに出力
        end
    end
end

-- メイン実行関数
-- config テーブルの内容:
--   effectA (関数, オプショナル)
--   effectB (関数, オプショナル)
--   effectC (関数, オプショナル)
--   pack (0: まとめない, 1: 範囲外の文字をまとめる, 2: すべての文字をまとめる)
function M.execute(config)
    -- 個別オブジェクトが有効かを確認
    local is_multi = obj.getoption("multi_object")
    if not is_multi then
        debug_print("個別オブジェクトが有効ではないため、「個別エフェクト追加」処理をスキップします。")
        return
    end

    local idx   = obj.index
    local last  = obj.num - 1
    local total_char = obj.num
    local current_char = idx + 1

    -- 先行フィルタ（group_effect_common）から範囲情報を取得
    local startA = _G.gi_startA or 1
    local endA   = _G.gi_endA or 1
    local startB = _G.gi_startB or 1
    local endB   = _G.gi_endB or 1
    local startC = _G.gi_startC or 1
    local endC   = _G.gi_endC or 1

    local sA = _G.gi_sA or math.min(startA, endA)
    local eA = _G.gi_eA or math.min(math.max(startA, endA), total_char)
    local sB = _G.gi_sB or math.min(startB, endB)
    local eB = _G.gi_eB or math.min(math.max(startB, endB), total_char)
    local sC = _G.gi_sC or math.min(startC, endC)
    local eC = _G.gi_eC or math.min(math.max(startC, endC), total_char)

    -- 中心座標のフォールバック
    if not _G.gi_cx_A then
        local cx, cy = get_group_center(startA, endA)
        _G.gi_cx_A = cx; _G.gi_cy_A = cy
    end
    if not _G.gi_cx_B then
        local cx, cy = get_group_center(startB, endB)
        _G.gi_cx_B = cx; _G.gi_cy_B = cy
    end
    if not _G.gi_cx_C then
        local cx, cy = get_group_center(startC, endC)
        _G.gi_cx_C = cx; _G.gi_cy_C = cy
    end

    -- 合成バッファサイズ
    local full_w = _G.gi_full_w or obj.screen_w
    local full_h = _G.gi_full_h or obj.screen_h

    local inA = (current_char >= sA and current_char <= eA)
    local inB = (current_char >= sB and current_char <= eB)
    local inC = (current_char >= sC and current_char <= eC)

    local pack = config.pack or 0

    -- 最初の文字(index == 0)で pack 関連フラグを初期化
    if idx == 0 then
        _G.gi_has_packed_A = false
        _G.gi_has_packed_B = false
        _G.gi_has_packed_C = false
    end

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

    -- 各グループまたはグループ外の分岐処理
    if inA then
        process_add_group("A", current_char, idx, sA, eA, full_w, full_h, pack, config.effectA)
    elseif inB then
        process_add_group("B", current_char, idx, sB, eB, full_w, full_h, pack, config.effectB)
    elseif inC then
        process_add_group("C", current_char, idx, sC, eC, full_w, full_h, pack, config.effectC)
    elseif idx <= last then
        if pack == 2 then
            -- 範囲外文字をキャッシュして不可視化
            -- 先行フィルタによって文字は既に full_w x full_h バッファ内の正しい位置に配置されているため、
            -- 追加オフセットなし (0,0,0,1,1,0,0,0) でキャッシュに描画・保存する
            obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
            obj.clearbuffer("tempbuffer")
            obj.ox = 0; obj.oy = 0; obj.oz = 0; obj.rx = 0; obj.ry = 0; obj.rz = 0; obj.cx = 0; obj.cy = 0
            obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
            obj.copybuffer("cache:gi_other_" .. idx, "tempbuffer")
            obj.setoption("drawtarget", "framebuffer")
            obj.load("tempbuffer")
            obj.clearbuffer("object")

        elseif pack == 1 then
            if idx < last_other_idx then
                -- 最後の範囲外文字ではない場合: キャッシュに保存して不可視化
                obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
                obj.clearbuffer("tempbuffer")
                obj.ox = 0; obj.oy = 0; obj.oz = 0; obj.rx = 0; obj.ry = 0; obj.rz = 0; obj.cx = 0; obj.cy = 0
                obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                obj.copybuffer("cache:gi_other_" .. idx, "tempbuffer")
                obj.setoption("drawtarget", "framebuffer")
                obj.load("tempbuffer")
                obj.clearbuffer("object")
            else
                -- 最後の範囲外文字の場合: これまでの範囲外文字キャッシュと現在の文字を合成して出力
                obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
                obj.clearbuffer("tempbuffer")
                for i = 0, idx - 1 do
                    local c = i + 1
                    local is_in_grp = (c >= sA and c <= eA) or (c >= sB and c <= eB) or (c >= sC and c <= eC)
                    if not is_in_grp then
                        if obj.copybuffer("object", "cache:gi_other_" .. i) then
                            obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                        end
                    end
                end
                -- 現在の文字 (最後の範囲外文字) をオフセットなしで描画
                obj.ox = 0; obj.oy = 0; obj.oz = 0; obj.rx = 0; obj.ry = 0; obj.rz = 0; obj.cx = 0; obj.cy = 0
                obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                obj.setoption("drawtarget", "framebuffer")
                obj.load("tempbuffer")
                obj.clearbuffer("tempbuffer")
            end
        else
            -- pack == 0: まとめない（先行フィルタの出力をそのまま描画）
        end
    else
        return
    end

    -- pack == 2: 最後の文字のタイミングで全グループ＋範囲外文字を文字順序どおりに1枚に合成
    if pack == 2 and idx == last then
        obj.setoption("drawtarget", "tempbuffer", full_w, full_h)
        obj.clearbuffer("tempbuffer")

        local drawn_A = false
        local drawn_B = false
        local drawn_C = false

        for i = 0, obj.num - 1 do
            local c = i + 1
            if c == eA and not drawn_A then
                if _G.gi_has_packed_A and obj.copybuffer("object", "cache:packed_group_A") then
                    obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                end
                drawn_A = true
            elseif c == eB and not drawn_B then
                if _G.gi_has_packed_B and obj.copybuffer("object", "cache:packed_group_B") then
                    obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                end
                drawn_B = true
            elseif c == eC and not drawn_C then
                if _G.gi_has_packed_C and obj.copybuffer("object", "cache:packed_group_C") then
                    obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                end
                drawn_C = true
            else
                local is_in_grp = (c >= sA and c <= eA) or (c >= sB and c <= eB) or (c >= sC and c <= eC)
                if not is_in_grp then
                    if obj.copybuffer("object", "cache:gi_other_" .. i) then
                        obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
                    end
                end
            end
        end

        -- グループ終了文字がループ外などの安全対策
        if not drawn_A and _G.gi_has_packed_A and obj.copybuffer("object", "cache:packed_group_A") then
            obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
        end
        if not drawn_B and _G.gi_has_packed_B and obj.copybuffer("object", "cache:packed_group_B") then
            obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
        end
        if not drawn_C and _G.gi_has_packed_C and obj.copybuffer("object", "cache:packed_group_C") then
            obj.draw(0, 0, 0, 1, 1, 0, 0, 0)
        end

        obj.setoption("drawtarget", "framebuffer")
        obj.load("tempbuffer")
        obj.clearbuffer("tempbuffer")
    end
end

return M
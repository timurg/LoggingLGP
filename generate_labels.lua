function generate_labels(tag, timestamp, record)
    -- Проверяем наличие полей и устанавливаем значения по умолчанию
    record["level"] = record["Level"] or "info"          -- Устанавливаем "info", если Level отсутствует
    record["source"] = record["SourceContext"] or "unknown" -- Устанавливаем "unknown", если SourceContext отсутствует
    record["app"] = record["Application"] or "unknown"   -- Устанавливаем "unknown", если Application отсутствует

    -- Оставляем dealId как обычное поле лога, а не метку
    if record["dealId"] then
        record["deal_id"] = tostring(record["dealId"])   -- Преобразуем dealId в строку
    else
        record["deal_id"] = "0"                         -- Устанавливаем значение по умолчанию
    end

    -- Возвращаем измененный рекорд
    return 1, timestamp, record
end
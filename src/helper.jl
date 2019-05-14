# base URL of the Binance API
BINANCE_MAIN = "https://www.binance.com/"
BINANCE_API_REST = "https://api.binance.com/"

function dict2str(dict::Dict)
    join(["$k=$v" for (k, v) in dict], "&")
end

function datetime2int64(datetime::DateTime)
    Int64(floor(datetime2unix(datetime) * 1000))
end # function

function int642datetime(time::Int64)
    unix2datetime(time / 1000)
end

# signing with apiKey and apiSecret
function timestamp()
    datetime2int64(now(UTC))
end

function hmac(key::Vector{UInt8}, msg::Vector{UInt8}, hash, blocksize::Int=64)
    if length(key) > blocksize
        key = hash(key)
    end

    pad = blocksize - length(key)

    if pad > 0
        resize!(key, blocksize)
        key[end - pad + 1:end] = 0
    end

    o_key_pad = key .⊻ 0x5c
    i_key_pad = key .⊻ 0x36

    hash([o_key_pad; hash([i_key_pad; msg])])
end

function dosign(queryString, apiSecret)
    bytes2hex(hmac(Vector{UInt8}(apiSecret), Vector{UInt8}(queryString), SHA.sha256))
end


# function HTTP response 2 JSON
function r2j(response)
    JSON.parse(String(response))
end

function str2period(interval::String)
    period = parse(Int, interval[1:end-1])
    type = interval[end]
    if type == 'm'
        Minute(period)
    elseif type == 'h'
        Hour(period)
    elseif type == 'd'
        Day(period)
    elseif type == 'w'
        Week(period)
    elseif type == 'M'
        Month(period)
    else
        throw(ArgumentError("invalid interval: $interval"))
    end
end # function

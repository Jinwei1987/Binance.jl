module Websocket
using Dates, DataFrames, Printf
import HTTP, SHA, JSON

export
wstraderaw

include("helper.jl")

BINANCE_API_USER_DATA_STREAM = string(BINANCE_API_REST, "api/v1/userDataStream")


BINANCE_API_WS = "wss://stream.binance.com:9443/ws/"
#BINANCE_API_STREAM = "wss://stream.binance.com:9443/stream/"






# Websockets functions

function wsFunction(channel::Channel, ws::String, symbol::String)
    HTTP.WebSockets.open(string(BINANCE_API_WS, lowercase(symbol), ws); verbose=false) do io
      while !eof(io);
        put!(channel, r2j(readavailable(io)))
    end
  end
end

function wsTradeAgg(channel::Channel, symbol::String)
    wsFunction(channel, "@aggTrade", symbol)
end

function wstraderaw(channel::Channel, symbol::String)
    wsFunction(channel, "@trade", symbol)
end

function wsDepth(channel::Channel, symbol::String; level=5)
    wsFunction(channel, string("@depth", level), symbol)
end

function wsDepthDiff(channel::Channel, symbol::String)
    wsFunction(channel, "@depth", symbol)
end

function wsTicker(channel::Channel, symbol::String)
    wsFunction(channel, "@ticker", symbol)
end

function wsTicker24Hr(channel::Channel)
    HTTP.WebSockets.open(string(BINANCE_API_WS, "!ticker@arr"); verbose=false) do io
      while !eof(io);
        put!(channel, r2j(readavailable(io)))
    end
  end
end

function wsKline(channel::Channel, symbol::String; interval="1m")
  #interval => 1m 3m 5m 15m 30m 1h 2h 4h 6h 8h 12h 1d 3d 1w 1M
    wsFunction(channel, string("@kline_", interval), symbol)
end

function wsKlineStreams(channel::Channel, symbols::Array, interval="1m")
  #interval => 1m 3m 5m 15m 30m 1h 2h 4h 6h 8h 12h 1d 3d 1w 1M
    allStreams = map(s -> string(lowercase(s), "@kline_", interval), symbols)
    error = false;
    while !error
        try
            HTTP.WebSockets.open(string(BINANCE_API_WS,join(allStreams, "/")); verbose=false) do io
            while !eof(io);
                put!(channel, String(readavailable(io)))
            end
      end
        catch e
            println(e)
            error=true;
            println("error occured bailing wsklinestreams !")
        end
    end
end

function wsKlineStreams(callback::Function, symbols::Array; interval="1m")
    #interval => 1m 3m 5m 15m 30m 1h 2h 4h 6h 8h 12h 1d 3d 1w 1M
      allStreams = map(s -> string(lowercase(s), "@kline_", interval), symbols)
      @async begin
        HTTP.WebSockets.open(string("wss://stream.binance.com:9443/ws/",join(allStreams, "/")); verbose=false) do io
            while !eof(io)
                    data = String(readavailable(io))
                    callback(data)
            end
        end
    end
end

function openUserData(apiKey)
    headers = Dict("X-MBX-APIKEY" => apiKey)
    r = HTTP.request("POST", BINANCE_API_USER_DATA_STREAM, headers)
    return r2j(r.body)["listenKey"]
end

function keepAlive(apiKey, listenKey)
    if length(listenKey) == 0
        return false
    end

    headers = Dict("X-MBX-APIKEY" => apiKey)
    body = string("listenKey=", listenKey)
    r = HTTP.request("PUT", BINANCE_API_USER_DATA_STREAM, headers, body)
    return true
end

function closeUserData(apiKey, listenKey)
    if length(listenKey) == 0
        return false
    end
    headers = Dict("X-MBX-APIKEY" => apiKey)
    body = string("listenKey=", listenKey)
    r = HTTP.request("DELETE", BINANCE_API_USER_DATA_STREAM, headers, body)
   return true
end

function wsUserData(channel::Channel, apiKey, listenKey; reconnect=true)

    function keepAlive()
        keepAlive(apiKey, listenKey)
    end

    Timer(keepAlive, 1800; interval = 1800)

    error = false;
    while !error
        try
            HTTP.WebSockets.open(string(Binance.BINANCE_API_WS, listenKey); verbose=false) do io
                while !eof(io);
                    put!(channel, r2j(readavailable(io)))
                end
            end
        catch x
            println(x)
            error = true;
        end
    end

    if reconnect
        wsUserData(channel, apikey, openUserData(apiKey))
    end

end

end  # module Websocket

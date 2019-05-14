##################### PUBLIC CALL's #####################
module Client
using Dates, DataFrames, Printf
import HTTP, SHA, JSON

export
ping,
servertime,
get24hr,
getallprices,
getallbookticks,
getmarket,
getklines,
gethistklines

include("helper.jl")

function requestget(uri::String, params::Dict=Dict())
    r = HTTP.get(uri, query=dict2str(params))
    r2j(r.body)
end # function

function api(version::String, endpoint::String)
    "$(BINANCE_API_REST)api/$version/$endpoint"
end

function apiv1(endpoint::String)
    api("v1", endpoint)
end

function requestgetapi(version::String, endpoint::String, params::Dict=Dict())
    requestget(api(version, endpoint), params)
end # function

function requestgetv1(endpoint::String, params::Dict=Dict())
    requestget(apiv1(endpoint), params)
end # function

# Simple test if binance API is online
function ping()
    r = HTTP.get(apiv1("ping"))
    r.status
end

# Binance servertime
function servertime()
    result = requestgetv1("time")
    unix2datetime(result["serverTime"] / 1000)
end

function get24hr(symbol::Union{String, Nothing}=nothing)
    params = symbol!=nothing ? Dict("symbol" => symbol) : Dict()
    requestgetv1("ticker/24hr", params)
end

function getallprices()
    requestgetv1("ticker/allPrices")
end

function getallbookticks()
    requestgetv1("ticker/allBookTickers")
end

function getmarket(symbol::Union{String, Nothing}=nothing)
    params = symbol!=nothing ? Dict("symbol" => symbol) : Dict()
    r = requestget("$(BINANCE_MAIN)exchange/public/product", params)
    r["data"]
end

# binance get candlesticks/klines data
function getklines(symbol::String; starttime::Union{DateTime, Nothing}=nothing,
    endtime::Union{DateTime, Nothing}=nothing,
    interval::String="1m", limit::Int=500)

    params = Dict("symbol" => symbol, "interval" => interval, "limit" => limit)
    if starttime != nothing
        params["startTime"] = datetime2int64(starttime)
    end
    if endtime != nothing
        params["endTime"] = datetime2int64(endtime)
    end
    r = requestgetv1("klines", params)
    for d in r
        d[1] = int642datetime(d[1])
        d[7] = int642datetime(d[7])
    end
    r
end

function earliest_timestamp(symbol::String, interval::String)
    kline = getklines(symbol, starttime=unix2datetime(0),
    interval=interval, limit=1)
    return kline[1][1]
end

function gethistklines(symbol::String, interval::String,
    starttime::DateTime, endtime::Union{DateTime, Nothing}=nothing,
    limit::Int=500)
    output = []
    period = str2period(interval)
    earliesttime = earliest_timestamp(symbol, interval)
    startTime = max(starttime, earliesttime)
    idx = 0
    while true
        tempdata = getklines(symbol, starttime=starttime,
        endtime=endtime, interval=interval, limit=limit)
        if length(tempdata) == 0
            break
        end
        output = [output; tempdata]
        if length(tempdata) < limit
            break
        end
        starttime = tempdata[end][1] + period
        idx += 1
        if idx % 3 == 0
            sleep(0.5)
        end
    end
    output
end # function

##################### SECURED CALL's NEEDS apiKey / apiSecret #####################
function createOrder(symbol::String, orderSide::String;
    quantity::Float64=0.0, orderType::String = "LIMIT",
    price::Float64=0.0, stopPrice::Float64=0.0,
    icebergQty::Float64=0.0, newClientOrderId::String="")

      if quantity <= 0.0
          error("Quantity cannot be <=0 for order type.")
      end

      println("$orderSide => $symbol q: $quantity, p: $price ")

      order = Dict("symbol"           => symbol,
                      "side"             => orderSide,
                      "type"             => orderType,
                      "quantity"         => @sprintf("%.8f", quantity),
                      "newOrderRespType" => "FULL",
                      "recvWindow"       => 10000)

      if newClientOrderId != ""
          order["newClientOrderId"] = newClientOrderId;
      end

      if orderType == "LIMIT" || orderType == "LIMIT_MAKER"
          if price <= 0.0
              error("Price cannot be <= 0 for order type.")
          end
          order["price"] =  @sprintf("%.8f", price)
      end

      if orderType == "STOP_LOSS" || orderType == "TAKE_PROFIT"
          if stopPrice <= 0.0
              error("StopPrice cannot be <= 0 for order type.")
          end
          order["stopPrice"] = @sprintf("%.8f", stopPrice)
      end

      if orderType == "STOP_LOSS_LIMIT" || orderType == "TAKE_PROFIT_LIMIT"
          if price <= 0.0 || stopPrice <= 0.0
              error("Price / StopPrice cannot be <= 0 for order type.")
          end
          order["price"] =  @sprintf("%.8f", price)
          order["stopPrice"] =  @sprintf("%.8f", stopPrice)
      end

      if orderType == "TAKE_PROFIT"
          if price <= 0.0 || stopPrice <= 0.0
              error("Price / StopPrice cannot be <= 0 for STOP_LOSS_LIMIT order type.")
          end
          order["price"] =  @sprintf("%.8f", price)
          order["stopPrice"] =  @sprintf("%.8f", stopPrice)
      end

      if orderType == "LIMIT"  || orderType == "STOP_LOSS_LIMIT" || orderType == "TAKE_PROFIT_LIMIT"
          order["timeInForce"] = "GTC"
      end

      order
  end

# account call contains balances
function account(apiKey::String, apiSecret::String)
    headers = Dict("X-MBX-APIKEY" => apiKey)

    query = string("recvWindow=5000&timestamp=", timestamp())

    r = HTTP.request("GET", string(BINANCE_API_REST, "api/v3/account?", query, "&signature=", dosign(query, apiSecret)), headers)

    if r.status != 200
        println(r)
        return status
    end

    return r2j(r.body)
end

function executeOrder(order::Dict, apiKey, apiSecret; execute=false)
    headers = Dict("X-MBX-APIKEY" => apiKey)
    query = string(dict2str(order), "&timestamp=", timestamp())
    body = string(query, "&signature=", dosign(query, apiSecret))
    println(body)

    uri = "api/v3/order/test"
    if execute
        uri = "api/v3/order"
    end

    r = HTTP.request("POST", string(BINANCE_API_REST, uri), headers, body)
    r2j(r.body)
end

# returns default balances with amounts > 0
function balances(apiKey::String, apiSecret::String; balanceFilter = x -> parse(Float64, x["free"]) > 0.0 || parse(Float64, x["locked"]) > 0.0)
    acc = account(apiKey,apiSecret)
    balances = filter(balanceFilter, acc["balances"])
end

# helper
filterOnRegex(matcher, withDictArr; withKey="symbol") = filter(x -> match(Regex(matcher), x[withKey]) != nothing, withDictArr);

function coinmarketcap(;quantity=-1)
    num = ["last_updated","price_usd","24h_volume_usd","market_cap_usd","rank","available_supply","total_supply","max_supply","percent_change_1h","percent_change_24h","percent_change_7d"]

    query = ""
    if quantity > 0
        query="?limit=$quantity"
    end

    r = HTTP.request("GET", string("https://api.coinmarketcap.com/v1/ticker/",query))
    market = r2j(r.body)
    agg = nothing
    columns = nothing
    for m in market
        result = map(z -> z.second == nothing ? missing : (z.first in num ? parse(Float64, z.second) : z.second), collect(m))
        #r = DataFrame(map(z -> [z.second == nothing ? missing : (z.first in num ? parse(Float64, z.second) : z.second)], collect(m)), map(symbol -> Symbol(symbol), collect(keys(m))))
        if agg == nothing
            agg = hcat(result...)
            columns= map(symbol -> Symbol(symbol), collect(keys(m)))
        else
            agg = vcat(agg, hcat(result...))
        end
    end

    df = DataFrame(agg, columns);
    df[:last_updated] = Dates.unix2datetime.(df[:last_updated])
    return df
end

#https://gist.github.com/abel30567/060c861a8e8db6f1ab6f88febbb78c8c
function hodlN(N;cap=0.1)
    market = coinmarketcap(quantity=N)

    assetSize = size(market,1)

    market[:ratio] = market[:market_cap_usd] / sum(market[:market_cap_usd])

    ratios = market[:ratio]

    for i in range(1, assetSize-1)
        if ratios[i]  > cap
            overflow = ratios[i] - cap
            ratios[i] = cap

            total_nested_cap = sum(market[:market_cap_usd][i+1:end])
            market[:ratio][i+1:end] += overflow * market[:market_cap_usd][i+1:end] / total_nested_cap
        end
    end
    market
end

end

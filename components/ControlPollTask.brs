sub init()
    m.top.functionName = "pollControl"
end sub

sub pollControl()
    config = m.top.config
    if not isAssociativeArray(config)
        return
    end if

    controlUrl = trimText(config.controlUrl)
    if controlUrl = ""
        return
    end if

    pollId = trimText(config.pollId)
    intervalMs = clampInterval(config.intervalMs)
    delayPort = CreateObject("roMessagePort")
    sequence = 0

    while m.top.active = true and m.top.control = "RUN"
        commandName = fetchCommand(controlUrl)
        if commandName = "reload" or commandName = "stop"
            sequence = sequence + 1
            m.top.command = {
                seq: sequence
                name: commandName
                pollId: pollId
            }
        end if

        wait(intervalMs, delayPort)
    end while
end sub

function fetchCommand(controlUrl as string) as string
    xfer = CreateObject("roUrlTransfer")
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.AddHeader("Accept", "application/json, text/plain")
    xfer.SetUrl(controlUrl)

    body = xfer.GetToString()
    if body = invalid
        return ""
    end if

    json = ParseJson(body)
    if isAssociativeArray(json)
        return normalizeCommand(firstJsonString(json, ["command", "action", "type"]))
    end if

    return normalizeCommand(body)
end function

function normalizeCommand(value as dynamic) as string
    commandName = lcase(trimText(value))
    if commandName = "noop" or commandName = "reload" or commandName = "stop"
        return commandName
    end if

    return ""
end function

function firstJsonString(payload as object, keys as object) as string
    for each key in keys
        if payload.DoesExist(key)
            value = trimText(payload[key])
            if value <> ""
                return value
            end if
        end if
    end for

    return ""
end function

function clampInterval(value as dynamic) as integer
    intervalMs = 1500

    if type(value) = "Integer"
        intervalMs = value
    else if trimText(value) <> ""
        intervalMs = val(trimText(value))
    end if

    if intervalMs < 1000 then intervalMs = 1000
    if intervalMs > 2000 then intervalMs = 2000

    return intervalMs
end function

function trimText(value as dynamic) as string
    if value = invalid then return ""

    valueType = type(value)
    if valueType = "String" or valueType = "roString"
        return value.Trim()
    end if

    return ""
end function

function isAssociativeArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifAssociativeArray") <> invalid
end function

sub init()
    m.top.functionName = "fetchSession"
end sub

sub fetchSession()
    response = {
        success: false
        requestId: ""
        session: invalid
        errorMessage: "Missing session request."
    }

    request = m.top.request
    if not isAssociativeArray(request)
        print "[ScreenCastTV] session fetch failure src=<missing>"
        m.top.response = response
        return
    end if

    response.requestId = trimText(request.requestId)
    src = trimText(request.src)
    if src = ""
        response.errorMessage = "Missing session URL."
        print "[ScreenCastTV] session fetch failure src=<missing>"
        m.top.response = response
        return
    end if

    xfer = CreateObject("roUrlTransfer")
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.AddHeader("Accept", "application/json")
    xfer.SetUrl(src)

    body = xfer.GetToString()

    if body = invalid
        response.errorMessage = "Session request failed."
        print "[ScreenCastTV] session fetch failure src=" + src + " status=<unavailable>"
        m.top.response = response
        return
    end if

    payloadText = sanitizeJsonText(body)
    if payloadText = ""
        response.errorMessage = "Session endpoint returned an empty response."
        print "[ScreenCastTV] session fetch failure src=" + src + " empty body"
        m.top.response = response
        return
    end if

    json = ParseJson(payloadText)
    if isArray(json) and json.Count() > 0 and isAssociativeArray(json[0])
        json = json[0]
    end if

    if not isAssociativeArray(json)
        response.errorMessage = "Session endpoint returned non-JSON content."
        print "[ScreenCastTV] session fetch failure src=" + src + " invalid JSON body=" + previewText(payloadText, 180)
        m.top.response = response
        return
    end if

    response.success = true
    response.session = json
    response.errorMessage = ""

    print "[ScreenCastTV] session fetch success src=" + src
    m.top.response = response
end sub

function trimText(value as dynamic) as string
    if value = invalid then return ""

    valueType = type(value)
    if valueType = "String" or valueType = "roString"
        return value.Trim()
    end if

    return ""
end function

function sanitizeJsonText(value as dynamic) as string
    return trimText(value)
end function

function previewText(value as dynamic, maxLength = 120 as integer) as string
    text = trimText(value)
    if text = "" then return "<empty>"

    if Len(text) <= maxLength
        return text
    end if

    return Left(text, maxLength) + "..."
end function

function integerToString(value as dynamic) as string
    if value = invalid then return "0"
    if type(value) = "Integer" then return value.ToStr()
    return trimText(value)
end function

function isAssociativeArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifAssociativeArray") <> invalid
end function

function isArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifArray") <> invalid
end function

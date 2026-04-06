sub Main(args as dynamic)
    launchParams = normalizeLaunchArgs(args)

    print "[ScreenCastTV] app launch version=1.1.14"
    print "[ScreenCastTV] parsed params " + summarizeLaunchParams(launchParams)

    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    scene.launchParams = launchParams

    screen.Show()

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed()
                return
            end if
        end if
    end while
end sub

function normalizeLaunchArgs(args as dynamic) as object
    lookup = {}
    flattenLaunchArgs(args, lookup)

    return {
        contentID: firstNonEmptyLookup(lookup, ["contentid", "content_id"])
        mediaType: firstNonEmptyLookup(lookup, ["mediatype", "media_type"])
        src: firstNonEmptyLookup(lookup, ["src", "source", "sessionurl", "session_url"])
        title: firstNonEmptyLookup(lookup, ["title"])
        kind: firstNonEmptyLookup(lookup, ["kind"])
    }
end function

sub flattenLaunchArgs(value as dynamic, lookup as object)
    if value = invalid then return

    if isAssociativeArray(value)
        for each key in value
            item = value[key]
            lowerKey = lcase(key)

            if hasText(item)
                text = trimText(item)
                if text <> ""
                    lookup[lowerKey] = text
                    if shouldParseQueryValue(lowerKey, text)
                        queryLookup = parseQueryString(text)
                        mergeLookups(lookup, queryLookup)
                    end if
                end if
            else if isAssociativeArray(item) or isArray(item)
                flattenLaunchArgs(item, lookup)
            end if
        end for
    else if isArray(value)
        for each item in value
            flattenLaunchArgs(item, lookup)
        end for
    else if hasText(value)
        text = trimText(value)
        if shouldParseFreeformQuery(text)
            queryLookup = parseQueryString(text)
            mergeLookups(lookup, queryLookup)
        end if
    end if
end sub

function shouldParseQueryValue(key as string, value as string) as boolean
    if value = "" then return false

    if key = "query" or key = "params" or key = "dialparams" or key = "payload" or key = "extras"
        return true
    end if

    if Left(value, 1) = "?"
        return true
    end if

    lowered = lcase(value)
    if Left(lowered, 4) = "http"
        return false
    end if

    return shouldParseFreeformQuery(value)
end function

function shouldParseFreeformQuery(value as string) as boolean
    if value = "" then return false

    lowered = lcase(value)
    if instr(1, lowered, "contentid=") > 0 then return true
    if instr(1, lowered, "mediatype=") > 0 then return true
    if instr(1, lowered, "src=") > 0 then return true

    return false
end function

function parseQueryString(rawValue as string) as object
    result = {}
    query = trimText(rawValue)
    if query = "" then return result

    questionMark = instr(1, query, "?")
    if questionMark > 0 and questionMark < len(query)
        query = Mid(query, questionMark + 1)
    else if questionMark = len(query)
        query = ""
    end if

    if query = "" then return result

    pairs = query.Split("&")
    for each pair in pairs
        if pair <> invalid
            separator = instr(1, pair, "=")
            if separator > 0
                key = lcase(urlDecode(Left(pair, separator - 1)))
                value = urlDecode(Mid(pair, separator + 1))

                if key <> "" and value <> ""
                    result[key] = value
                end if
            end if
        end if
    end for

    return result
end function

function urlDecode(encoded as string) as string
    decoded = ""
    length = len(encoded)
    index = 1

    while index <= length
        currentChar = Mid(encoded, index, 1)

        if currentChar = "+"
            decoded = decoded + " "
            index = index + 1
        else if currentChar = "%" and index + 2 <= length
            hexPair = Mid(encoded, index + 1, 2)
            if isHexPair(hexPair)
                decoded = decoded + Chr(Val("&h" + hexPair))
                index = index + 3
            else
                decoded = decoded + currentChar
                index = index + 1
            end if
        else
            decoded = decoded + currentChar
            index = index + 1
        end if
    end while

    return decoded
end function

function isHexPair(value as string) as boolean
    if len(value) <> 2 then return false

    allowed = "0123456789abcdefABCDEF"
    firstChar = Mid(value, 1, 1)
    secondChar = Mid(value, 2, 1)

    return instr(1, allowed, firstChar) > 0 and instr(1, allowed, secondChar) > 0
end function

sub mergeLookups(target as object, source as object)
    for each key in source
        if source[key] <> invalid and source[key] <> ""
            target[key] = source[key]
        end if
    end for
end sub

function firstNonEmptyLookup(lookup as object, keys as object) as string
    for each key in keys
        if lookup.DoesExist(key)
            value = trimText(lookup[key])
            if value <> ""
                return value
            end if
        end if
    end for

    return ""
end function

function summarizeLaunchParams(params as object) as string
    return "contentID=" + displayValue(params.contentID) + ", mediaType=" + displayValue(params.mediaType) + ", src=" + displayValue(params.src) + ", title=" + displayValue(params.title) + ", kind=" + displayValue(params.kind)
end function

function displayValue(value as dynamic) as string
    text = trimText(value)
    if text = "" then return "<none>"
    return text
end function

function hasText(value as dynamic) as boolean
    return trimText(value) <> ""
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

function isArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifArray") <> invalid
end function

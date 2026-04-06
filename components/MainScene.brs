sub init()
    m.top.setFocus(true)

    m.video = m.top.findNode("video")
    m.photoPosterA = m.top.findNode("photoPosterA")
    m.photoPosterB = m.top.findNode("photoPosterB")
    m.overlay = m.top.findNode("overlay")
    m.overlayScrim = m.top.findNode("overlayScrim")
    m.bootSplashGroup = m.top.findNode("bootSplashGroup")
    m.standbyGroup = m.top.findNode("standbyGroup")
    m.statusPanelGroup = m.top.findNode("statusPanelGroup")
    m.panelAccent = m.top.findNode("panelAccent")
    m.statusPill = m.top.findNode("statusPill")
    m.statusLabel = m.top.findNode("statusLabel")
    m.eyebrowLabel = m.top.findNode("eyebrowLabel")
    m.spinner = m.top.findNode("spinner")
    m.titleLabel = m.top.findNode("titleLabel")
    m.messageLabel = m.top.findNode("messageLabel")
    m.hintLabel = m.top.findNode("hintLabel")
    m.bootTimer = m.top.findNode("bootTimer")
    m.sessionTask = m.top.findNode("sessionTask")
    m.controlTask = m.top.findNode("controlTask")

    m.state = "boot"
    m.currentLaunchParams = invalid
    m.currentSession = invalid
    m.currentTitle = "Ready to connect"
    m.retryContext = invalid
    m.requestCounter = 0
    m.pendingRequestId = ""
    m.activePollId = ""
    m.lastCommandSeq = 0
    m.lastVideoState = ""
    m.lastPhotoLoadStatusA = ""
    m.lastPhotoLoadStatusB = ""
    m.activePhotoSlot = ""
    m.pendingPhotoSlot = ""
    m.ignoreStoppedTransition = false

    if m.eyebrowLabel <> invalid
        m.eyebrowLabel.text = "TV Screen Mirror & Cast"
    end if

    m.top.observeField("launchParams", "onLaunchParamsChanged")
    if m.bootTimer <> invalid
        m.bootTimer.observeField("fire", "onBootTimerFired")
    end if
    m.sessionTask.observeField("response", "onSessionTaskResponse")
    m.controlTask.observeField("command", "onControlCommand")
    m.video.observeField("state", "onVideoStateChanged")
    m.photoPosterA.observeField("loadStatus", "onPhotoPosterALoadStatusChanged")
    m.photoPosterB.observeField("loadStatus", "onPhotoPosterBLoadStatusChanged")

    showBootSplash()

    if m.top.launchParams <> invalid
        onLaunchParamsChanged()
    end if
end sub

sub onLaunchParamsChanged()
    launchWithParams(m.top.launchParams)
end sub

sub launchWithParams(params as dynamic)
    if not isAssociativeArray(params)
        m.retryContext = invalid
        if m.state <> "boot"
            showIdleState()
        end if
        return
    end if

    m.currentLaunchParams = params
    sessionSrc = trimText(params.src)
    contentId = lowerText(params.contentID)
    hasLaunchIntent = hasText(sessionSrc) or hasText(params.contentID) or hasText(params.mediaType) or hasText(params.title) or hasText(params.kind)

    if isFetchableSessionSrc(sessionSrc)
        m.retryContext = params
        beginSessionFetch(params)
    else if contentId = "review-demo"
        m.retryContext = params
        playVideoSession(buildReviewDemoSession(params), params)
    else
        m.retryContext = invalid
        if hasText(sessionSrc)
            print "[ScreenCastTV] ignoring non-session src=" + sessionSrc
            showIdleState()
        else if hasLaunchIntent
            print "[ScreenCastTV] no valid launch params, showing idle"
            showIdleState()
        else if m.state <> "boot"
            print "[ScreenCastTV] no valid launch params, showing idle"
            showIdleState()
        end if
    end if
end sub

sub beginSessionFetch(params as object)
    preserveVisiblePhoto = shouldPreserveVisiblePhoto(params)
    prepareForPlaybackTransition(preserveVisiblePhoto)

    requestId = nextToken("session")
    m.pendingRequestId = requestId

    if preserveVisiblePhoto
        m.state = "playing"
        m.currentTitle = resolveDisplayTitle(invalid, params)
    else
        setViewState("loading", resolveDisplayTitle(invalid, params), "Loading session...", "Fetching ScreenCastTV session details.")
    end if

    m.sessionTask.control = "STOP"
    m.sessionTask.request = {
        src: trimText(params.src)
        requestId: requestId
    }
    m.sessionTask.control = "RUN"
end sub

sub onSessionTaskResponse()
    response = m.sessionTask.response
    if not isAssociativeArray(response) then return

    requestId = trimText(response.requestId)
    if requestId = "" or requestId <> m.pendingRequestId
        return
    end if

    if response.success = true and isAssociativeArray(response.session)
        playSession(response.session, m.currentLaunchParams)
    else
        showErrorState("Could not load session", fallbackText(response.errorMessage, "The session endpoint did not return a playable payload."))
    end if
end sub

sub playSession(session as object, params as object)
    if resolvePlaybackKind(session, params) = "photo"
        playPhotoSession(session, params)
        return
    end if

    playVideoSession(session, params)
end sub

sub playVideoSession(session as object, params as object)
    prepareForPlaybackTransition(false)

    content = buildVideoContent(session, params)
    if content = invalid
        showErrorState("Unsupported session", "The session did not include a playable HLS or video URL.")
        return
    end if

    m.currentSession = session
    m.currentLaunchParams = params
    m.retryContext = params
    m.currentTitle = fallbackText(content.title, resolveDisplayTitle(session, params))

    m.video.visible = true
    m.video.content = content
    m.video.control = "play"

    setViewState("loading", m.currentTitle, "Preparing playback...", "Waiting for the Roku video player to start.")
    startControlPolling(extractControlUrl(session))
end sub

sub playPhotoSession(session as object, params as object)
    preserveVisiblePhoto = hasVisiblePhotoPoster()
    prepareForPlaybackTransition(preserveVisiblePhoto)

    photoUrl = resolveMediaUrl(session)
    if photoUrl = ""
        showErrorState("Unsupported session", "The session did not include a playable photo URL.")
        return
    end if

    m.currentSession = session
    m.currentLaunchParams = params
    m.retryContext = params
    m.currentTitle = resolveDisplayTitle(session, params)

    targetSlot = m.activePhotoSlot
    if targetSlot = ""
        targetSlot = "A"
    end if
    targetPoster = photoPosterForSlot(targetSlot)
    if targetPoster = invalid
        targetSlot = inactivePhotoSlot()
        targetPoster = photoPosterForSlot(targetSlot)
    end if
    if targetPoster = invalid
        targetSlot = "A"
        targetPoster = m.photoPosterA
    end if

    resetPhotoLoadStatus(targetSlot)
    targetPoster.opacity = 1
    targetPoster.visible = true
    targetPoster.uri = photoUrl
    m.activePhotoSlot = targetSlot
    m.pendingPhotoSlot = ""

    inactiveSlot = inactivePhotoSlot()
    inactivePoster = photoPosterForSlot(inactiveSlot)
    if inactivePoster <> invalid and inactiveSlot <> "" and inactiveSlot <> targetSlot
        inactivePoster.uri = ""
        inactivePoster.opacity = 1
        inactivePoster.visible = false
        resetPhotoLoadStatus(inactiveSlot)
    end if

    print "[ScreenCastTV] photo update url=" + photoUrl
    setViewState("playing", m.currentTitle, "", "")
    startControlPolling(extractControlUrl(session))
end sub

sub startControlPolling(controlUrl as string)
    stopControlPolling()

    if not hasText(controlUrl)
        return
    end if

    pollId = nextToken("poll")
    m.activePollId = pollId
    m.lastCommandSeq = 0

    m.controlTask.config = {
        controlUrl: controlUrl
        intervalMs: 1500
        pollId: pollId
    }
    m.controlTask.active = true
    m.controlTask.control = "RUN"
end sub

sub stopControlPolling()
    m.activePollId = ""
    m.lastCommandSeq = 0

    m.controlTask.active = false
    m.controlTask.control = "STOP"
end sub

sub onControlCommand()
    commandEvent = m.controlTask.command
    if not isAssociativeArray(commandEvent) then return
    if trimText(commandEvent.pollId) <> m.activePollId then return

    seq = toInteger(commandEvent.seq)
    if seq <= m.lastCommandSeq then return
    m.lastCommandSeq = seq

    commandName = lowerText(commandEvent.name)
    if commandName = "reload"
        print "[ScreenCastTV] control command reload"
        if isAssociativeArray(m.retryContext)
            launchWithParams(m.retryContext)
        end if
    else if commandName = "stop"
        print "[ScreenCastTV] stop / back (control stop)"
        returnToIdle()
    end if
end sub

sub onVideoStateChanged()
    state = lowerText(m.video.state)
    if state = "" or state = m.lastVideoState
        return
    end if

    m.lastVideoState = state

    if state = "playing"
        print "[ScreenCastTV] playback start"
        setViewState("playing", m.currentTitle, "", "")
    else if state = "buffering"
        print "[ScreenCastTV] buffering"
        setViewState("buffering", m.currentTitle, "Buffering video...", "Network conditions changed. Playback should resume automatically.")
    else if state = "error"
        errorMessage = fallbackText(m.video.errorMsg, "The Roku video player could not start this stream.")
        print "[ScreenCastTV] playback error " + errorMessage
        showErrorState("Playback error", errorMessage)
    else if state = "finished"
        returnToIdle()
    else if state = "stopped"
        if m.ignoreStoppedTransition
            m.ignoreStoppedTransition = false
            return
        end if

        if m.state <> "idle" and m.state <> "error"
            showIdleState()
        end if
    end if
end sub

sub onPhotoPosterALoadStatusChanged()
    status = lowerText(m.photoPosterA.loadStatus)
    if status = "" or status = m.lastPhotoLoadStatusA then return

    m.lastPhotoLoadStatusA = status
    handlePhotoLoadStatusChange("A", m.photoPosterA)
end sub

sub onPhotoPosterBLoadStatusChanged()
    status = lowerText(m.photoPosterB.loadStatus)
    if status = "" or status = m.lastPhotoLoadStatusB then return

    m.lastPhotoLoadStatusB = status
    handlePhotoLoadStatusChange("B", m.photoPosterB)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press <> true then return false

    lowerKey = lcase(key)
    if lowerKey = "back"
        if m.state <> "idle" and m.state <> "boot"
            print "[ScreenCastTV] stop / back"
            returnToIdle()
            return true
        end if
    else if lowerKey = "ok" or lowerKey = "select" or lowerKey = "play"
        if m.state = "error" and isAssociativeArray(m.retryContext)
            launchWithParams(m.retryContext)
            return true
        end if
    end if

    return false
end function

sub returnToIdle()
    stopControlPolling()
    m.pendingRequestId = ""
    m.currentSession = invalid
    m.ignoreStoppedTransition = false
    clearPhotoPosters()

    if m.video <> invalid
        m.video.control = "stop"
        m.video.visible = false
    end if

    showIdleState()
end sub

sub prepareForPlaybackTransition(preserveVisiblePhoto = false as boolean)
    stopControlPolling()
    if m.bootTimer <> invalid
        m.bootTimer.control = "stop"
    end if
    m.pendingRequestId = ""
    m.lastVideoState = ""
    m.ignoreStoppedTransition = false

    if m.video <> invalid
        currentVideoState = lowerText(m.video.state)
        if currentVideoState <> "" and currentVideoState <> "none" and currentVideoState <> "stopped"
            m.ignoreStoppedTransition = true
            m.video.control = "stop"
        end if
        m.video.visible = false
    end if

    if preserveVisiblePhoto
        pendingPoster = photoPosterForSlot(m.pendingPhotoSlot)
        if pendingPoster <> invalid and m.pendingPhotoSlot <> "" and m.pendingPhotoSlot <> m.activePhotoSlot
            pendingPoster.uri = ""
            pendingPoster.opacity = 1
            pendingPoster.visible = false
        end if
        m.pendingPhotoSlot = ""
    else
        clearPhotoPosters()
    end if
end sub

sub showBootSplash()
    m.retryContext = invalid
    if m.bootTimer <> invalid
        m.bootTimer.control = "stop"
    end if
    setViewState("boot", "", "", "")
    if m.bootTimer <> invalid
        m.bootTimer.control = "start"
    end if
end sub

sub onBootTimerFired()
    if m.state = "boot"
        showIdleState()
    end if
end sub

sub showIdleState()
    if m.bootTimer <> invalid
        m.bootTimer.control = "stop"
    end if
    setViewState("idle", "Start from your iPhone", "Open Screen Mirroring: TV Air Cast on your iPhone to begin.", "Make sure your iPhone and Roku are on the same Wi-Fi.")
end sub

sub showErrorState(title as string, message as string)
    stopControlPolling()
    if m.bootTimer <> invalid
        m.bootTimer.control = "stop"
    end if

    if m.video <> invalid
        m.video.control = "stop"
        m.video.visible = false
    end if

    clearPhotoPosters()

    setViewState("error", title, message, "Press OK to retry or Back to return home.")
end sub

sub handlePhotoLoadStatusChange(posterSlot as string, poster as object)
    if poster = invalid then return

    status = lowerText(poster.loadStatus)
    if status = "ready"
        if posterSlot = m.activePhotoSlot or posterSlot = m.pendingPhotoSlot
            print "[ScreenCastTV] photo ready"
        end if
    else if status = "failed"
        print "[ScreenCastTV] playback error The Roku image viewer could not load this photo."
        if posterSlot = m.pendingPhotoSlot or posterSlot = m.activePhotoSlot
            poster.uri = ""
            poster.opacity = 1
            poster.visible = false
            m.pendingPhotoSlot = ""
            if posterSlot = m.activePhotoSlot
                m.activePhotoSlot = ""
            end if
        end if
        showErrorState("Playback error", "The Roku image viewer could not load this photo.")
    end if
end sub

sub clearPhotoPosters()
    m.activePhotoSlot = ""
    m.pendingPhotoSlot = ""
    m.lastPhotoLoadStatusA = ""
    m.lastPhotoLoadStatusB = ""

    if m.photoPosterA <> invalid
        m.photoPosterA.uri = ""
        m.photoPosterA.opacity = 1
        m.photoPosterA.visible = false
    end if

    if m.photoPosterB <> invalid
        m.photoPosterB.uri = ""
        m.photoPosterB.opacity = 1
        m.photoPosterB.visible = false
    end if
end sub

function photoPosterForSlot(slot as string) as object
    normalizedSlot = ucase(trimText(slot))
    if normalizedSlot = "A"
        return m.photoPosterA
    else if normalizedSlot = "B"
        return m.photoPosterB
    end if

    return invalid
end function

function inactivePhotoSlot() as string
    if m.activePhotoSlot = "" or m.activePhotoSlot = "B"
        return "A"
    end if

    return "B"
end function

function hasVisiblePhotoPoster() as boolean
    activePoster = photoPosterForSlot(m.activePhotoSlot)
    return activePoster <> invalid and activePoster.visible
end function

sub resetPhotoLoadStatus(slot as string)
    normalizedSlot = ucase(trimText(slot))
    if normalizedSlot = "A"
        m.lastPhotoLoadStatusA = ""
    else if normalizedSlot = "B"
        m.lastPhotoLoadStatusB = ""
    end if
end sub

function shouldPreserveVisiblePhoto(params as dynamic) as boolean
    if not hasVisiblePhotoPoster() then return false
    return resolvePlaybackKind(invalid, params) = "photo"
end function

sub setViewState(nextState as string, title as string, message as string, hint as string)
    m.state = nextState
    m.titleLabel.text = fallbackText(title, "ScreenCastTV Receiver")
    m.messageLabel.text = fallbackText(message, "")
    m.hintLabel.text = fallbackText(hint, "")
    if m.statusLabel <> invalid
        m.statusLabel.text = stateBadgeText(nextState)
    end if
    if m.statusPill <> invalid
        m.statusPill.color = stateBadgeColor(nextState)
    end if
    if m.panelAccent <> invalid
        m.panelAccent.color = stateAccentColor(nextState)
    end if

    if nextState = "playing"
        m.overlay.visible = false
        setOverlayGroupVisibility(false, false, false)
        m.spinner.visible = false
        m.spinner.control = "stop"
        return
    end if

    m.overlay.visible = true

    if nextState = "boot"
        m.overlayScrim.color = "0x09111C00"
        setOverlayGroupVisibility(true, false, false)
        m.spinner.visible = false
        m.spinner.control = "stop"
        return
    end if

    if nextState = "idle"
        m.overlayScrim.color = "0x060B1318"
        setOverlayGroupVisibility(false, true, false)
        m.spinner.visible = false
        m.spinner.control = "stop"
        return
    end if

    setOverlayGroupVisibility(false, false, true)

    if nextState = "buffering"
        m.overlayScrim.color = "0x09111C88"
        m.spinner.visible = true
        m.spinner.control = "start"
    else if nextState = "loading"
        m.overlayScrim.color = "0x09111CD6"
        m.spinner.visible = true
        m.spinner.control = "start"
    else if nextState = "error"
        m.overlayScrim.color = "0x1A0C12E6"
        m.spinner.visible = false
        m.spinner.control = "stop"
    else
        m.overlayScrim.color = "0x09111CD6"
        m.spinner.visible = false
        m.spinner.control = "stop"
    end if
end sub

sub setOverlayGroupVisibility(showBoot as boolean, showStandby as boolean, showStatus as boolean)
    if m.bootSplashGroup <> invalid
        m.bootSplashGroup.visible = showBoot
    end if

    if m.standbyGroup <> invalid
        m.standbyGroup.visible = showStandby
    end if

    if m.statusPanelGroup <> invalid
        m.statusPanelGroup.visible = showStatus
    end if
end sub

function buildReviewDemoSession(params as object) as object
    return {
        title: fallbackText(params.title, "ScreenCastTV Review Demo")
        description: "Public HLS demo stream for certification and deep-link testing."
        url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
        streamFormat: "hls"
        live: false
    }
end function

function buildVideoContent(session as object, params as object) as dynamic
    lookup = {}
    buildLookup(session, lookup)

    streamUrl = resolveMediaUrl(session)
    if streamUrl = ""
        return invalid
    end if

    streamFormat = normalizeStreamFormat(firstLookupString(lookup, ["streamformat", "stream_format", "format", "type"]), firstLookupString(lookup, ["mimetype", "mime_type", "mime"]), streamUrl)
    if streamFormat = ""
        streamFormat = "hls"
    end if

    content = CreateObject("roSGNode", "ContentNode")
    content.url = streamUrl
    content.streamFormat = streamFormat

    title = resolveDisplayTitle(session, params)
    if title <> ""
        content.title = title
        content.shortDescriptionLine1 = title
    end if

    description = firstLookupString(lookup, ["description", "summary", "subtitle"])
    if description <> ""
        content.description = description
        content.shortDescriptionLine2 = description
    end if

    posterUrl = firstLookupString(lookup, ["hdposterurl", "posterurl", "poster", "thumbnailurl", "thumbnail", "artworkurl"])
    if posterUrl <> ""
        content.hdposterurl = posterUrl
    end if

    if isLiveSession(session, params, lookup)
        content.live = true
    end if

    return content
end function

function resolveMediaUrl(session as object) as string
    lookup = {}
    buildLookup(session, lookup)
    return firstLookupString(lookup, ["streamurl", "stream_url", "playbackurl", "playback_url", "mediaurl", "media_url", "url", "src", "hls"])
end function

function extractControlUrl(session as object) as string
    lookup = {}
    buildLookup(session, lookup)
    return firstLookupString(lookup, ["controlurl", "control_url"])
end function

function resolveDisplayTitle(session as dynamic, params as dynamic) as string
    if isAssociativeArray(session)
        lookup = {}
        buildLookup(session, lookup)
        sessionTitle = firstLookupString(lookup, ["title", "name"])
        if sessionTitle <> ""
            return sessionTitle
        end if
    end if

    if isAssociativeArray(params)
        paramTitle = trimText(params.title)
        if paramTitle <> ""
            return paramTitle
        end if

        if lowerText(params.contentID) = "review-demo"
            return "ScreenCastTV Review Demo"
        end if
    end if

    return "TV Screen Mirror & Cast"
end function

function isLiveSession(session as object, params as object, lookup as object) as boolean
    if coerceBoolean(firstLookupValue(lookup, ["live", "islive", "is_live"]), false)
        return true
    end if

    if lowerText(params.kind) = "live" then return true

    mediaType = lowerText(params.mediaType)
    if mediaType = "live" or instr(1, mediaType, "live") > 0
        return true
    end if

    return false
end function

function resolvePlaybackKind(session as dynamic, params as dynamic) as string
    lookup = {}
    if isAssociativeArray(session)
        buildLookup(session, lookup)
    end if

    kind = lowerText(firstLookupString(lookup, ["kind"]))
    mediaType = lowerText(firstLookupString(lookup, ["mediatype", "media_type"]))
    mimeType = lowerText(firstLookupString(lookup, ["mimetype", "mime_type", "mime"]))
    sourceUrl = lcase(resolveMediaUrlFromLookup(lookup))

    if isAssociativeArray(params)
        if isPhotoDescriptor(lowerText(params.kind)) or isPhotoDescriptor(lowerText(params.mediaType))
            return "photo"
        end if
    end if

    if isPhotoDescriptor(kind) or isPhotoDescriptor(mediaType)
        return "photo"
    end if

    if Left(mimeType, 6) = "image/"
        return "photo"
    end if

    if hasImageExtension(sourceUrl)
        return "photo"
    end if

    return "video"
end function

function resolveMediaUrlFromLookup(lookup as object) as string
    return firstLookupString(lookup, ["streamurl", "stream_url", "playbackurl", "playback_url", "mediaurl", "media_url", "url", "src", "hls"])
end function

function isPhotoDescriptor(value as string) as boolean
    if value = "" then return false
    if instr(1, value, "photo") > 0 then return true
    if instr(1, value, "image") > 0 then return true
    return false
end function

function hasImageExtension(sourceUrl as string) as boolean
    if sourceUrl = "" then return false

    if instr(1, sourceUrl, ".jpg") > 0 then return true
    if instr(1, sourceUrl, ".jpeg") > 0 then return true
    if instr(1, sourceUrl, ".png") > 0 then return true
    if instr(1, sourceUrl, ".gif") > 0 then return true
    if instr(1, sourceUrl, ".webp") > 0 then return true

    return false
end function

sub buildLookup(value as dynamic, lookup as object)
    if value = invalid then return

    if isAssociativeArray(value)
        for each key in value
            item = value[key]
            lowerKey = lcase(key)

            if not lookup.DoesExist(lowerKey)
                if hasText(item) or type(item) = "Boolean"
                    lookup[lowerKey] = item
                end if
            end if

            if isAssociativeArray(item) or isArray(item)
                buildLookup(item, lookup)
            end if
        end for
    else if isArray(value)
        for each item in value
            buildLookup(item, lookup)
        end for
    end if
end sub

function firstLookupString(lookup as object, keys as object) as string
    value = firstLookupValue(lookup, keys)
    return trimText(value)
end function

function firstLookupValue(lookup as object, keys as object) as dynamic
    for each key in keys
        if lookup.DoesExist(key)
            return lookup[key]
        end if
    end for

    return invalid
end function

function normalizeStreamFormat(formatValue as string, mimeType as string, streamUrl as string) as string
    loweredFormat = lcase(formatValue)
    loweredMime = lcase(mimeType)
    loweredUrl = lcase(streamUrl)

    if loweredFormat = "ts" or loweredFormat = "mpegts" or loweredFormat = "transportstream"
        return "ts"
    end if

    if loweredMime = "video/mp2t"
        return "ts"
    end if

    if loweredFormat = "hls" or loweredFormat = "m3u8"
        return "hls"
    end if

    if loweredMime = "application/vnd.apple.mpegurl" or loweredMime = "application/x-mpegurl"
        return "hls"
    end if

    if loweredFormat = "mp4"
        return "mp4"
    end if

    if instr(1, loweredUrl, ".m3u8") > 0
        return "hls"
    end if

    if instr(1, loweredUrl, ".ts") > 0
        return "ts"
    end if

    if instr(1, loweredUrl, ".mp4") > 0
        return "mp4"
    end if

    return ""
end function

function nextToken(prefix as string) as string
    m.requestCounter = m.requestCounter + 1
    return prefix + "-" + m.requestCounter.ToStr()
end function

function stateBadgeText(nextState as string) as string
    if nextState = "idle" then return "Standby"
    if nextState = "loading" then return "Loading"
    if nextState = "buffering" then return "Buffering"
    if nextState = "playing" then return "Playing"
    if nextState = "error" then return "Attention"
    return "ScreenCastTV"
end function

function stateBadgeColor(nextState as string) as string
    if nextState = "loading" then return "0x234E7AFF"
    if nextState = "buffering" then return "0x615019FF"
    if nextState = "error" then return "0x6C2334FF"
    return "0x27405FFF"
end function

function stateAccentColor(nextState as string) as string
    if nextState = "loading" then return "0x58CCFFFF"
    if nextState = "buffering" then return "0xF2C14EFF"
    if nextState = "error" then return "0xF16C85FF"
    return "0x58CCFFFF"
end function

function fallbackText(value as dynamic, defaultValue as string) as string
    text = trimText(value)
    if text = "" then return defaultValue
    return text
end function

function hasText(value as dynamic) as boolean
    return trimText(value) <> ""
end function

function isFetchableSessionSrc(value as dynamic) as boolean
    src = lcase(trimText(value))
    if src = "" then return false
    return Left(src, 7) = "http://" or Left(src, 8) = "https://"
end function

function trimText(value as dynamic) as string
    if value = invalid then return ""

    valueType = type(value)
    if valueType = "String" or valueType = "roString"
        return value.Trim()
    end if

    return ""
end function

function lowerText(value as dynamic) as string
    return lcase(trimText(value))
end function

function coerceBoolean(value as dynamic, defaultValue as boolean) as boolean
    if value = invalid then return defaultValue
    if type(value) = "Boolean" then return value

    lowered = lowerText(value)
    if lowered = "true" or lowered = "1" or lowered = "yes"
        return true
    end if

    if lowered = "false" or lowered = "0" or lowered = "no"
        return false
    end if

    return defaultValue
end function

function toInteger(value as dynamic) as integer
    if value = invalid then return 0

    if type(value) = "Integer"
        return value
    end if

    if hasText(value)
        return val(trimText(value))
    end if

    return 0
end function

function isAssociativeArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifAssociativeArray") <> invalid
end function

function isArray(value as dynamic) as boolean
    if value = invalid then return false
    return GetInterface(value, "ifArray") <> invalid
end function

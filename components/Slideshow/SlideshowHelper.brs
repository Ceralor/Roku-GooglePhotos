'*************************************************************
'** PhotoView for Google Photos
'** Copyright (c) 2017-2018 Chris Taylor.  All rights reserved.
'** Use of code within this application subject to the MIT License (MIT)
'** https://raw.githubusercontent.com/chtaylo2/Roku-GooglePhotos/master/LICENSE
'*************************************************************

' This is our slideshow function declaration script.
' Since ROKU doesn't support global functions, the following must be added to each XML file where needed
' <script type="text/brightscript" uri="pkg:/components/Utils/SlideshowHelper.brs" />


'*********************************************************
'**
'** OAUTH HANDLERS
'**
'*********************************************************

Sub doRefreshToken(post_data=[] as Object, selectedUser=-1 as Integer)
    print "SlideshowHelper.brs [doRefreshToken]"

    params = "client_id="                  + m.clientId
    params = params + "&client_secret="    + m.clientSecret
    params = params + "&grant_type="       + "refresh_token"
    
    if selectedUser<>-1 then
        params = params + "&refresh_token="    + m.refreshToken[selectedUser]
    else
        params = params + "&refresh_token="    + m.refreshToken[m.global.selectedUser]
    end if

    makeRequest({}, m.oauth_prefix+"/token", "POST", params, 2, post_data)
End Sub


Function handleRefreshToken(event as object)
    print "SlideshowHelper.brs [handleRefreshToken]"

    status = -1
    errorMsg = ""
    refreshData = m.UriHandler.refreshToken
    
    if refreshData <> invalid
        if (refreshData.code <> 200) and (refreshData.code <> 400)
            errorMsg = "An Error Occurred in 'handleRefreshToken'. Code: "+(refreshData.code).toStr()+" - " +refreshData.error
        else if refreshData.code = 400
            'CODE: 400 - Google will not allow us to use refresh token. Likely expired.
            m.screenActive          = createObject("roSGNode", "ExpiredPopup")
            m.screenActive.id       = "ExpiredPopup"
            m.top.appendChild(m.screenActive)
            m.screenActive.setFocus(true)
        else
            json = ParseJson(refreshData.content)
            if json = invalid
                errorMsg = "Unable to parse Json response: handleRefreshToken"
                status = 1
            else if type(json) <> "roAssociativeArray"
                errorMsg = "Json response is not an associative array: handleRefreshToken"
                status = -1
            else if json.DoesExist("error")
                errorMsg = "Json error response: [handleRefreshToken] " + json.error
                status = 1
            else
                status = 0
                ' We have our tokens
                
                if refreshData.post_data[0]<>invalid and (refreshData.post_data[0] = "doGetScreensaverAlbumList" or refreshData.post_data[0] = "doGetScreensaverAlbumImages" or refreshData.post_data[0] = "doGetAlbumSelection") then
                    'Don't use global set user. Screensaver uses this.
                    m.accessToken[refreshData.post_data[1]]  = getString(json,"access_token")
                else
                    m.accessToken[m.global.selectedUser]  = getString(json,"access_token")
                end if
                    
                m.tokenType          = getString(json,"token_type")
                m.tokenExpiresIn     = getInteger(json,"expires_in")
                refreshToken         = getString(json,"refresh_token")
                
                if refreshToken <> ""
                        m.refreshToken[m.global.selectedUser] = refreshToken
                end if
    
                'Query User info
                'status = m.RequestUserInfo(m.accessToken.Count()-1, false)
    
                'Save cached values to registry
                saveReg()
            end if
        end if
    end if
    
    if errorMsg<>"" then
        'ShowNotice
        m.noticeDialog.visible = true
        buttons =  [ "OK" ]
        m.noticeDialog.message = errorMsg
        m.noticeDialog.buttons = buttons
        m.noticeDialog.setFocus(true)
        m.noticeDialog.observeField("buttonSelected","noticeClose")
    end if   
    
    if status = 0 then
        if refreshData.post_data[0] = "doGetScreensaverAlbumList" then
            doGetScreensaverAlbumList(refreshData.post_data[1])
        else if refreshData.post_data[0] = "doGetScreensaverAlbumImages" then
            doGetScreensaverAlbumImages(refreshData.post_data[1], refreshData.post_data[2])
        else if refreshData.post_data[0] = "doGetLibraryImages" then
            doGetLibraryImages(refreshData.post_data[1], refreshData.post_data[2])
        else if refreshData.post_data[0] = "doGetAlbumImages" then
            doGetAlbumImages(refreshData.post_data[1], refreshData.post_data[2])
        else if refreshData.post_data[0] = "doGetSearch" then
            doGetSearch(refreshData.post_data[1])
        else if refreshData.post_data[0] = "doGetAlbumSelection" then
            doGetAlbumSelection()
        else
            doGetAlbumList()
        end if
    end if
    
End Function


'*********************************************************
'**
'** ALBUM HANDLERS
'**
'*********************************************************

' URL Request to fetch album listing
Sub doGetAlbumList(pageNext="" As String)
    print "Albums.brs [doGetAlbumList]"  

    tmpData = [ "doGetAlbumList" ]

    params = "pageSize=50"
    if pageNext<>"" then
        params = params + "&pageToken=" + pageNext
    end if

    signedHeader = oauth_sign(m.global.selectedUser)
    makeRequest(signedHeader, m.gp_prefix + "/albums?"+params, "GET", "", 0, tmpData)
End Sub


' Create full album list from XML response
Function googleAlbumListing(jsonlist As Object) As Object
    albumlist=CreateObject("roList")
    
    'print formatJSON(jsonlist)
    for each record in jsonlist["albums"]
        album=googleAlbumCreateRecord(record)

        if album.GetImageCount > 0 then
            ' Do not show photos from Google Hangout albums or any marked with "Private" in name
            if album.GetTitle.instr("Hangout:") = -1 and album.GetTitle.instr("rivate") = -1 then
                albumlist.Push(album)
            end if
        end if
    next
    
    return albumlist
End Function


' Create single album record from JSON entry
Function googleAlbumCreateRecord(json As Object) As Object
    album               = CreateObject("roAssociativeArray")
    album.GetTitle      = getString(json,"title")
    album.GetID         = getString(json,"id")
    album.GetImageCount = Val(getString(json,"mediaItemsCount"))
    album.GetThumb      = getString(json,"coverPhotoBaseUrl")+getResolution("SD")
        
    return album
End Function


' ********************************************************************
' **
' ** IMAGE HANDLERS
' **
' ********************************************************************

Sub doGetLibraryImages(pageNext="" As String)
    print "Albums.brs - [doGetLibraryImages]"
    
    print "GooglePhotos pageNext: "; pageNext

    tmpData = [ "doGetLibraryImages", m.albumActiveObject, pageNext ]

    params = "pageSize=100"
    if pageNext<>"" then
        params = params + "&pageToken=" + pageNext
    else
        'First query, reset MetaData
        m.videosMetaData    = []
        m.imagesMetaData    = []
    end if
    
    signedHeader = oauth_sign(m.global.selectedUser)
    makeRequest(signedHeader, m.gp_prefix + "/mediaItems?"+params, "GET", "", 1, tmpData)
End Sub


Sub doGetAlbumImages(albumid As String, pageNext="" As String)
    print "Albums.brs - [doGetAlbumImages]"

    print "GooglePhotos pageNext: "; pageNext

    tmpData = [ "doGetAlbumImages", m.albumActiveObject, pageNext ]

    params = "pageSize=100"
    params = params + "&albumId=" + albumid
    if pageNext<>"" then
        params = params + "&pageToken=" + pageNext
    else
        'First query, reset MetaData
        m.videosMetaData    = []
        m.imagesMetaData    = []
    end if
    
    signedHeader = oauth_sign(m.global.selectedUser)
    makeRequest(signedHeader, m.gp_prefix + "/mediaItems:search/", "POST", params, 1, tmpData)
End Sub


Function googleImageListing(jsonlist As Object) As Object
    images=CreateObject("roList")
    for each record in jsonlist["mediaItems"]
        image=googleImageCreateRecord(record)
        if image.GetURL<>invalid then
            images.Push(image)
        end if
    next
    
    return images
End Function


Function googleImageCreateRecord(json As Object) As Object
    image                = CreateObject("roAssociativeArray")
    image.GetTitle       = ""
    image.GetID          = getString(json,"id")
    image.GetDescription = getString(json,"description")
    image.GetURL         = getString(json,"baseUrl")
    image.GetFilename    = getString(json,"filename")
    image.GetTimestamp   = getString(json["mediaMetadata"],"creationTime")
    image.IsVideo        = (json["mediaMetadata"]["video"]<>invalid)
    image.GetVideoStatus = getString(json["mediaMetadata"]["video"],"status")
    
    return image
End Function

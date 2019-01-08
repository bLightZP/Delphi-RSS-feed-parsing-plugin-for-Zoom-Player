{$I RSS_PLUGIN_DEFINES.INC}
unit rss_api;

interface

uses classes, tntclasses, strutils, sysutils, tntsysutils;

const
{$IFDEF LOCALTRACE}
  LogInit              : String = 'c:\log\.RSS_Reader_plugin.txt';
{$ENDIF}
  RSS_MAX_DESCRIPTION  : Integer = 3500;

Type
  TRSSEntryRecord =
  Record
    rsseType         : Integer;
    //rssePublishOrder : Integer;
    rssePublishDate  : TDateTime;
    rsseTitle        : WideString;
    rsseDescription  : WideString;
    rsseURL          : WideString;
    rsseThumbnail    : WideString;
    rsseDuration     : Integer;
  End;
  PRSSEntryRecord = ^TRSSEntryRecord;


//function ParseRSSFile(FileName : WideString; var rssTitle,rssDescription : WideString; var rssImage : String; var rssList : TList) : Boolean;
function ParseRSSStream(fStream : TStream; var rssTitle,rssDescription : WideString; var rssImage : String; rssList : TList) : Boolean;
function RSSdurationToSeconds(rssDuration : String) : Integer;
function RSSrecordToString(Entry : PRSSEntryRecord) : WideString;
function LoadRSSListFromFile(var rList : TList; FileName : WideString) : Boolean;
function SaveRSSListToFile(rList : TList; FileName : WideString) : Boolean;


implementation

uses misc_utils_unit, IdGlobalProtocols;

const
  rssEntryPrefix : String = 'RSSEntry';

function RSSdurationToSeconds(rssDuration : String) : Integer;
var
  sList : TStringList;
begin
  Result := 0;
  sList := TStringList.Create;
  Split(rssDuration,':',sList);

  If sList.Count = 3 then
  Begin
    Result := (StrToIntDef(sList[0],0)*3600)+(StrToIntDef(sList[1],0)*60)+(StrToIntDef(sList[2],0));
  End
    else
  If sList.Count = 2 then
  Begin
    Result := (StrToIntDef(sList[0],0)*60)+(StrToIntDef(sList[1],0));
  End
    else
  If sList.Count = 1 then
  Begin
    Result := StrToIntDef(sList[0],0);
  End;

  sList.Free;
end;


function ParseRSSStream(fStream : TStream; var rssTitle,rssDescription : WideString; var rssImage : String; rssList : TList) : Boolean;

  function DecodeCData(S : WideString) : WideString;
  var
    iPosS : Integer;
    iPosE : Integer;
  begin
    iPosS := Pos('<![CDATA[',S);
    If iPosS > 0 then
    Begin
      iPosE := PosEx(']]>',S,iPosS+9);
      If (iPosE > 0) then
      Begin
        Result := Copy(S,iPosS+9,(iPosE-iPosS)-9);
      End
      Else Result := S;
    End
    Else Result := S;
  end;

var
  sList     : TTNTStringList;
  sSrc      : WideString;
  sSrcL     : WideString;
  sChannel  : WideString;
  sChannelL : WideString;
  sItem     : WideString;
  sItemL    : WideString;
  nEntry    : PRSSEntryRecord;
  I,I1,I2   : Integer;
  iParse    : Integer;
  Found     : Boolean;
  CacheHit  : Boolean;
  {$IFDEF LOCALTRACE}
  newEntries: Integer;
  {$ENDIF}
begin
  Result   := False;

  sList := TTNTStringList.Create;
  Try sList.LoadFromStream(fStream); Except End;

  If sList.Count > 0 then
  Begin
    Result := True;

    //sSrc  := TNT_WideStringReplace(sList.Text,#9,'',[rfReplaceAll]);
    //sSrc  := TNT_WideStringReplace(sSrc,#10,'',[rfReplaceAll]);
    //sSrc  := TNT_WideStringReplace(sSrc,#13,'',[rfReplaceAll]);
    sSrc  := sList.Text;
    sSrcL := TNT_WideLowercase(sSrc);

    I  := Pos('<channel>',sSrcL);
    I1 := Pos('</channel>',sSrcL);

    If (I > 0) and (I1 > 0) then sChannel  := Copy(sSrc,I+9,(I1-I)-9) else sChannel  := sSrc;
    sChannelL := TNT_WideLowercase(sChannel);

    Begin
      // Find first entry
      iParse := Pos('<item>',sChannelL);
      If iParse = 0 then iParse := Pos('<entry>',sChannelL);
      If iParse > 0 then
      Begin
        // At least one item found
        rssTitle       := '';
        rssDescription := '';

        // Search for Channel Title before first entry
        I  := Pos('<title>',sChannelL);
        I1 := Pos('</title>',sChannelL);
        If (I > 0) and (I1 > 0) and (I1 < iParse) then rssTitle       := DecodeCData(UTF8StringToWideString(HTMLUnicodeToUTF8(Copy(sChannel,I+ 7,(I1-I)- 7))));

        // Search for Channel Description before first entry
        I  := Pos('<description>',sChannelL);
        I1 := Pos('</description>',sChannelL);
        If (I > 0) and (I1 > 0) and (I1 < iParse) then rssDescription := DecodeCData(UTF8StringToWideString(HTMLUnicodeToUTF8(Copy(sChannel,I+13,(I1-I)-13))));

        // Search for Channel Image #1 before first entry
        I  := Pos('<image>',sChannelL);
        I1 := Pos('</image>',sChannelL);
        If (I > 0) and (I1 > 0) and (I1 < iParse) then
        Begin
          I  := PosEx('<url>',sChannelL,I);
          I1 := PosEx('</url>',sChannelL,I);

          If (I > 0) and (I1 > 0) and (I1 < iParse) then rssImage := DecodeCData(Copy(sChannel,I+5,(I1-I)-5));
        End;

        // Search for Channel Image #2 before first entry
        I  := Pos('<itunes:image',sChannelL);
        If (I > 0) and (I < iParse) then
        Begin
          I  := PosEx('href="',sChannelL,I+1);
          I1 := PosEx('"',sChannelL,I+6);
          If (I > 0) and (I1 > 0) then rssImage := DecodeCData(Copy(sChannel,I+6,(I1-I)-6));
        End;

        {$IFDEF LOCALTRACE}
        DebugMsgFT(LogInit,'RSS Channel information:');
        DebugMsgFT(LogInit,'Title : '+rssTitle);
        DebugMsgFT(LogInit,'Desc  : '+rssDescription);
        DebugMsgFT(LogInit,'Image : '+rssImage+CRLF);
        newEntries := 0;
        {$ENDIF}

        // Search for items
        If rssList <> nil then
        Begin
          Repeat
            Found := False;
            I  := PosEx('<item>',sChannelL,iParse);
            I2 := 6;
            I1 := PosEx('</item>',sChannelL,iParse+I2);

            If (I = 0) or (I1 = 0) then
            Begin
              I  := PosEx('<entry>',sChannelL,iParse);
              I2 := 7;
              I1 := PosEx('</entry>',sChannelL,iParse+I2);
            End;


            If (I > 0) and (I1 > 0) then
            Begin
              Found  := True;
              sItem  := Copy(sChannel,I+I2,(I1-I)-I2);
              sItemL := TNT_WideLowercase(sItem);
              iParse := I1+I2+1; // position after </item>

              New(nEntry);
              nEntry^.rsseType         := 0;
              //nEntry^.rssePublishOrder := $FFFFFF-rssList.Count;
              nEntry^.rssePublishDate  := 0;
              nEntry^.rsseTitle        := '';
              nEntry^.rsseURL          := '';
              nEntry^.rsseDescription  := '';
              nEntry^.rsseDuration     := 0;
              nEntry^.rsseThumbnail    := '';

              // Item Title
              I  := Pos('<title>',sItemL);
              I1 := Pos('</title>',sItemL);
              If (I > 0) and (I1 > 0) then
              Begin
                nEntry^.rsseTitle := Trim(DecodeCData(UTF8StringToWideString(HTMLUnicodeToUTF8(Copy(sItem,I+ 7,(I1-I)- 7)))));
                nEntry^.rsseTitle := TNT_WideStringReplace(nEntry^.rsseTitle,CRLF,'\n',[rfReplaceAll]);
                nEntry^.rsseTitle := TNT_WideStringReplace(nEntry^.rsseTitle,#10,'\n',[rfReplaceAll]);
              End;

              // Item Link
              {I  := Pos('<link>',sItemL);
              I1 := Pos('</link>',sItemL);
              If (I > 0) and (I1 > 0) then nEntry^.rsseURL         := DecodeCData(Copy(sItem,I+ 6,(I1-I)- 6));}

              // Media Link
              I  := Pos('<enclosure',sItemL);
              If (I > 0) then
              Begin
                I  := PosEx('url="',sItemL,I+1);
                I1 := PosEx('"',sItemL,I+5);
                If (I > 0) and (I1 > 0) then nEntry^.rsseURL       := DecodeCData(Copy(sItem,I+5,(I1-I)-5));
              End;

              // Item Thumbnail
              I  := Pos('<media:thumbnail',sItemL);
              If (I > 0) then
              Begin
                I  := PosEx('url="',sItemL,I+1);
                I1 := PosEx('"',sItemL,I+5);
                If (I > 0) and (I1 > 0) then nEntry^.rsseThumbnail := DecodeCData(Copy(sItem,I+5,(I1-I)-5));
              End;

              // Item Thumbnail #2
              I  := Pos('<itunes:image',sItemL);
              If (I > 0) then
              Begin
                I  := PosEx('href="',sItemL,I+1);
                I1 := PosEx('"',sItemL,I+6);
                If (I > 0) and (I1 > 0) then nEntry^.rsseThumbnail := DecodeCData(Copy(sItem,I+6,(I1-I)-6));
              End;

              // Item Content
              I  := Pos('<media:content',sItemL);
              If (I > 0) then
              Begin
                I  := PosEx('url="',sItemL,I+1);
                I1 := PosEx('"',sItemL,I+5);
                If (I > 0) and (I1 > 0) then nEntry^.rsseURL       := DecodeCData(Copy(sItem,I+5,(I1-I)-5));

                I  := PosEx('duration="',sItemL,I1+1);
                I1 := PosEx('"',sItemL,I+10);
                If (I > 0) and (I1 > 0) then nEntry^.rsseDuration  := StrToIntDef(DecodeCData(Copy(sItem,I+5,(I1-I)-5)),0);
              End;

              // Item Duration
              I  := Pos('<itunes:duration>',sItemL);
              I1 := Pos('</itunes:duration>',sItemL);
              If (I > 0) and (I1 > 0) then nEntry^.rsseDuration    := RSSdurationToSeconds(DecodeCData(Copy(sItem,I+17,(I1-I)-17)));

              // Item Description
              I  := Pos('<description>',sItemL);
              I1 := Pos('</description>',sItemL);
              If (I > 0) and (I1 > 0) then
              Begin
                nEntry^.rsseDescription := Trim(DecodeCData(UTF8StringToWideString(HTMLUnicodeToUTF8(Copy(sItem,I+13,(I1-I)-13)))));
                nEntry^.rsseDescription := TNT_WideStringReplace(nEntry^.rsseDescription,CRLF,'\n',[rfReplaceAll]);
                nEntry^.rsseDescription := TNT_WideStringReplace(nEntry^.rsseDescription,#10,'\n',[rfReplaceAll]);
                nEntry^.rsseDescription := TNT_WideStringReplace(nEntry^.rsseDescription,#13,'\n',[rfReplaceAll]);

                // Make sure the description isn't too long.
                If Length(nEntry^.rsseDescription) > RSS_MAX_DESCRIPTION then nEntry^.rsseDescription := Copy(nEntry^.rsseDescription,1,RSS_MAX_DESCRIPTION);
              End;

              I  := Pos('<pubdate>',sItemL);
              I1 := Pos('</pubdate>',sItemL);
              If (I > 0) and (I1 > 0) then
                nEntry^.rssePublishDate := StrInternetToDateTime(DecodeCData(Copy(sItem,I+9,(I1-I)-9)));

              I  := Pos('<published>',sItemL);
              I1 := Pos('</published>',sItemL);
              If (I > 0) and (I1 > 0) then
                nEntry^.rssePublishDate := StrInternetToDateTime(DecodeCData(Copy(sItem,I+11,(I1-I)-11)));

              // Add to list
              If (nEntry^.rsseTitle <> '') and (nEntry^.rsseURL <> '') then
              Begin
                // Skip cached entries
                CacheHit := False;
                For I := 0 to rssList.Count-1 do
                Begin
                  If (nEntry^.rsseTitle = PRSSEntryRecord(rssList[I])^.rsseTitle) and (nEntry^.rsseURL = PRSSEntryRecord(rssList[I])^.rsseURL) then
                  Begin
                    CacheHit := True;
                    Break;
                  End;
                End;

                {$IFDEF LOCALTRACE}
                If CacheHit = False then
                Begin
                  DebugMsgFT(LogInit,'New RSS Entry:');
                  DebugMsgFT(LogInit,'Title     : '+nEntry^.rsseTitle);
                  DebugMsgFT(LogInit,'URL       : '+nEntry^.rsseURL);
                  DebugMsgFT(LogInit,'Date      : '+DateTimeToStr(nEntry^.rssePublishDate));
                  DebugMsgFT(LogInit,'Duration  : '+IntToStr(nEntry^.rsseDuration));
                  DebugMsgFT(LogInit,'Thumb     : '+nEntry^.rsseThumbnail);
                  DebugMsgFT(LogInit,'Desc      : '+nEntry^.rsseDescription+CRLF);
                  //DebugMsgFT(LogInit,'Order     : '+IntToStr(nEntry^.rssePublishOrder)+CRLF);
                  Inc(newEntries);
                End
                Else DebugMsgFT(LogInit,'Skipping duplicate entry "'+nEntry^.rsseTitle+'/'+nEntry^.rsseURL+'"'+CRLF);
                {$ENDIF}
                If CacheHit = False then rssList.Add(nEntry) else Dispose(nEntry);
              End
                else
              Begin
                {$IFDEF LOCALTRACE}
                DebugMsgFT(LogInit,'Invalid RSS Entry:');
                DebugMsgFT(LogInit,'Title     : '+nEntry^.rsseTitle);
                DebugMsgFT(LogInit,'URL       : '+nEntry^.rsseURL);
                DebugMsgFT(LogInit,'Date      : '+DateTimeToStr(nEntry^.rssePublishDate));
                DebugMsgFT(LogInit,'Duration  : '+IntToStr(nEntry^.rsseDuration));
                DebugMsgFT(LogInit,'Thumb     : '+nEntry^.rsseThumbnail);
                DebugMsgFT(LogInit,'Desc      : '+nEntry^.rsseDescription+CRLF);
                //DebugMsgFT(LogInit,'Order     : '+IntToStr(nEntry^.rssePublishOrder)+CRLF);
                {$ENDIF}
                Dispose(nEntry);
              End;
            End;
          Until Found = False;
        End;
        {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,IntToStr(newEntries)+' new entries found');{$ENDIF}
      End;
    End;
  End;
  sList.Free;
end;


function RSSrecordToCacheString(Entry : PRSSEntryRecord) : WideString;
begin
  With Entry^ do
  Begin
    Result :=  rssEntryPrefix+
              '("Type='+IntToStr(rsseType)+'",'+
               //'"PublishOrder='+IntToStr(rssePublishOrder)+'",'+
               '"PublishDate=' +FloatToStr(rssePublishDate)+'",'+
               '"Title='       +EncodeTextTags(rsseTitle,True)+'",'+
               '"Description=' +EncodeTextTags(rsseDescription,True)+'",'+
               '"URL='         +rsseURL+'",'+
               '"Thumbnail='   +rsseThumbnail+'",'+
               '"Duration='    +IntToStr(rsseDuration)+'")';
  End;
end;


procedure CacheStringToRSSRecord(S : WideString; var Entry : PRSSEntryRecord);
var
  I1     : Integer;
  pCount : Integer;
  S1,S2  : WideString;
begin
  pCount := SParamCount(S);

  With Entry^ do For I1 := 1 to pCount do
  Begin
    S1 := GetSParam(I1,S,False);
    S2 := TNT_WideLowercase(GetSLeftParam(S1));
    If S2 = 'type'         then rsseType         := StrToInt(GetSRightParam(S1,True));
    //If S2 = 'publishorder' then rssePublishOrder := StrToInt(GetSRightParam(S1,True));
    If S2 = 'publishdate'  then rssePublishDate  := StrToFloat(GetSRightParam(S1,True));
    If S2 = 'title'        then rsseTitle        := DecodeTextTags(GetSRightParam(S1,True),True);
    If S2 = 'description'  then rsseDescription  := DecodeTextTags(GetSRightParam(S1,True),True);
    If S2 = 'url'          then rsseURL          := GetSRightParam(S1,True);
    If S2 = 'thumbnail'    then rsseThumbnail    := GetSRightParam(S1,True);
    If S2 = 'duration'     then rsseDuration     := StrToInt(GetSRightParam(S1,True));
  End;
end;


function RSSrecordToString(Entry : PRSSEntryRecord) : WideString;
const
  niAudio     = 2;
  niVideo     = 3;

var
  sDuration   : String;
  sMediaType  : String;
  sExt        : String;

Begin
  // [MetaEntry1]  :  // Displayed in the meta-data's Title area
  // [MetaEntry2]  :  // Displayed in the meta-data's Date area
  // [MetaEntry3]  :  // Displayed in the meta-data's Duration
  // [MetaEntry4]  :  // Displayed in the meta-data's Genre/Type area
  // [MetaEntry5]  :  // Displayed in the meta-data's Overview/Description area
  // [MetaEntry6]  :  // Displayed in the meta-data's Actors/Media info area
  // [MetaRating]  :  // Meta rating, value of 0-100, 0=disabled

  If Entry^.rsseDuration > 0 then sDuration := EncodeDuration(Entry^.rsseDuration) else sDuration := '';

  sMediaType := '';
  sExt       := Lowercase(ExtractFileExt(Entry^.rsseURL));

  // Force media type for popular formats, otherwise media type is based on the category 
  If (sExt = '.mp3') or (sExt = '.weba') or (sExt = '.aac') or (sExt = '.flac') or (sExt = '.ogg') then sMediaType := '"MediaType='+IntToStr(niAudio)+'",';
  If (sExt = '.mp4') or (sExt = '.mkv')  or (sExt = '.wmv') or (sExt = '.webm') or (sExt = '.avi') or (sExt = '.mov') then sMediaType := '"MediaType='+IntToStr(niVideo)+'",';

  Result := '"Type='        +IntToStr(Entry^.rsseType)+'",'+sMediaType+
            '"Path='        +Entry^.rsseURL+'",'+
            '"Title='       +EncodeTextTags(Entry^.rsseTitle,True)+'",'+
            '"Description=' +EncodeTextTags(Entry^.rsseDescription,True)+'",'+
            '"Thumbnail='   +Entry^.rsseThumbnail+'",'+
            //'"Date='        +FloatToStr(Entry^.rssePublishOrder)+'",'+
            '"Date='        +FloatToStr(Entry^.rssePublishDate)+'",'+
            '"Duration='    +IntToStr(Entry^.rsseDuration)+'",'+
            '"Date='        +FloatToStr(Entry^.rssePublishDate)+'",'+
            '"MetaEntry1='  +EncodeTextTags(Entry^.rsseTitle,True)+'",'+
            '"MetaEntry2='  +DateToStr(Entry^.rssePublishDate)+'",'+
            '"MetaEntry3='  +sDuration+'",'+
            '"MetaEntry4=!",'+
            '"MetaEntry5='  +EncodeTextTags(Entry^.rsseDescription,True)+'",'+
            '"MetaEntry6=!"';
End;


function SaveRSSListToFile(rList : TList; FileName : WideString) : Boolean;
var
  I       : Integer;
  sList   : TTNTStringList;
  sPath   : WideString;
begin
  Result := False;
  sList := TTNTStringList.Create;

  For I := 0 to rList.Count-1 do sList.Add(RSSrecordToCacheString(PRSSEntryRecord(rList[I])));

  // Make sure the cache folder exists before writing to it
  sPath := WideExtractFilePath(FileName);
  If WideDirectoryExists(sPath) = False then WideForceDirectories(sPath);

  Try
    sList.SaveToFile(FileName);
    Result := True;
  Except
    Result := False;
  End;
  sList.Free;
end;


function LoadRSSListFromFile(var rList : TList; FileName : WideString) : Boolean;
var
  I      : Integer;
  sList  : TTNTStringList;
  nEntry : PRSSEntryRecord;
begin
  Result := False;
  If WideFileExists(FileName) = True then
  Begin
    sList := TTNTStringList.Create;

    Try
      sList.LoadFromFile(FileName);
    Except
    End;

    //For I := sList.Count-1 downto 0 do If Pos(Lowercase(rssEntryPrefix),Lowercase(sList[I])) = 1 then
    For I := 0 to sList.Count-1 do If Pos(Lowercase(rssEntryPrefix),Lowercase(sList[I])) = 1 then
    Begin
      New(nEntry);
      CacheStringToRSSRecord(sList[I],nEntry);
      rList.Add(nEntry);
    End;
    sList.Free;
  End;
end;


{function ParseRSSFile(FileName : WideString; var rssTitle,rssDescription : WideString; var rssImage : String; var rssList : TList) : Boolean;
var
  fList  : TTNTFileStream;
begin
  Result := False;
  Try
    fList := TTNTFileStream.Create(FileName,fmOpenRead or fmShareDenyNone);
  Except
    fList := nil;
  End;

  If fList <> nil then
  Begin
    Result := ParseRSSStream(fList,rssTitle,rssDescription,rssImage,rssList);
    fList.Free;
  End;
end;}


end.

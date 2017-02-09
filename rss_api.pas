{$I RSS_PLUGIN_DEFINES.INC}
unit rss_api;

interface

uses classes, tntclasses, strutils, sysutils, tntsysutils;

{$IFDEF LOCALTRACE}
const
  LogInit : String = 'c:\log\.RSS_Reader_plugin.txt';
{$ENDIF}

Type
  TRSSEntryRecord =
  Record
    rsseType         : Integer;
    rssePublishOrder : Integer;
    rssePublishDate  : WideString;
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


implementation

uses misc_utils_unit;


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
    Result := StrToIntDef(sList[1],0);
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

        // Search for Channel Image before first entry
        I  := Pos('<image>',sChannelL);
        I1 := Pos('</image>',sChannelL);
        If (I > 0) and (I1 > 0) and (I1 < iParse) then
        Begin
          I  := PosEx('<url>',sChannelL,I);
          I1 := PosEx('</url>',sChannelL,I);

          If (I > 0) and (I1 > 0) and (I1 < iParse) then rssImage := DecodeCData(Copy(sChannel,I+5,(I1-I)-5));
        End;

        {$IFDEF LOCALTRACE}
        DebugMsgFT(LogInit,'RSS Channel information:');
        DebugMsgFT(LogInit,'Title : '+rssTitle);
        DebugMsgFT(LogInit,'Desc  : '+rssDescription);
        DebugMsgFT(LogInit,'Image : '+rssImage+CRLF);
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
              nEntry^.rssePublishOrder := $FFFFFF-rssList.Count;
              nEntry^.rssePublishDate  := '';
              nEntry^.rsseTitle        := '';
              nEntry^.rsseURL          := '';
              nEntry^.rsseDescription  := '';
              nEntry^.rsseDuration     := 0;
              nEntry^.rsseThumbnail    := '';

              // Item Title
              I  := Pos('<title>',sItemL);
              I1 := Pos('</title>',sItemL);
              If (I > 0) and (I1 > 0) then nEntry^.rsseTitle       := DecodeCData(UTF8StringToWideString(HTMLUnicodeToUTF8(Copy(sItem,I+ 7,(I1-I)- 7))));

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
              If (I > 0) and (I1 > 0) then nEntry^.rsseDescription := DecodeCData(UTF8StringToWideString(HTMLUnicodeToUTF8(Copy(sItem,I+13,(I1-I)-13))));

              I  := Pos('<pubdate>',sItemL);
              I1 := Pos('</pubdate>',sItemL);
              If (I > 0) and (I1 > 0) then nEntry^.rssePublishDate := DecodeCData(Copy(sItem,I+9,(I1-I)-9));

              // Add to list
              If (nEntry^.rsseTitle <> '') and (nEntry^.rsseURL <> '') then
              Begin
                {$IFDEF LOCALTRACE}
                DebugMsgFT(LogInit,'New RSS Entry:');
                DebugMsgFT(LogInit,'Title     : '+nEntry^.rsseTitle);
                DebugMsgFT(LogInit,'URL       : '+nEntry^.rsseURL);
                DebugMsgFT(LogInit,'Desc      : '+nEntry^.rsseDescription);
                DebugMsgFT(LogInit,'Date      : '+nEntry^.rssePublishDate);
                DebugMsgFT(LogInit,'Duration  : '+IntToStr(nEntry^.rsseDuration));
                DebugMsgFT(LogInit,'Thumb     : '+nEntry^.rsseThumbnail);
                DebugMsgFT(LogInit,'Order     : '+IntToStr(nEntry^.rssePublishOrder)+CRLF);
                {$ENDIF}
                rssList.Add(nEntry);
              End
              Else Dispose(nEntry);
            End;
          Until Found = False;
        End;  
      End;
    End;
  End;
  sList.Free;
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

{$I RSS_PLUGIN_DEFINES.INC}

     {********************************************************************
      | This Source Code is subject to the terms of the                  |
      | Mozilla Public License, v. 2.0. If a copy of the MPL was not     |
      | distributed with this file, You can obtain one at                |
      | https://mozilla.org/MPL/2.0/.                                    |
      |                                                                  |
      | Software distributed under the License is distributed on an      |
      | "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or   |
      | implied. See the License for the specific language governing     |
      | rights and limitations under the License.                        |
      ********************************************************************}


      { This Plugin uses the INDY 10 library to convert RFC822 dates to TDateTime.

        And the TNT Delphi Unicode Controls (compatiable with the last free version)
        to handle a few unicode tasks.

        And optionally, the FastMM/FastCode/FastMove libraries:
        http://sourceforge.net/projects/fastmm/
        }


library RSS_Feed;

uses
  FastMM4,
  FastMove,
  FastCode,
  Windows,
  SysUtils,
  Classes,
  Forms,
  Controls,
  DateUtils,
  SyncObjs,
  Dialogs,
  StrUtils,
  TNTClasses,
  TNTSysUtils,
  TNTSystem,
  WinInet,
  misc_utils_unit,
  rss_api;

{$R *.res}


Type
  TCategoryPluginRecord =
  Record
    CategoryInput : PChar;
    CategoryID    : PChar;
    CategoryTitle : PChar;
    CategoryThumb : PChar;
    DataPath      : PChar;
    Scrapers      : PChar;
    TextLines     : Integer;
    DefaultFlags  : Integer;
    SortMode      : Integer;
  End;
  PCategoryPluginRecord = ^TCategoryPluginRecord;

  TCategoryItemList =
  Record
    catItems      : PChar;
    // Format:
    // Each entry contains multiple parameters (listed below).
    // Entries are separated by the "|" character.
    // Any use of the quote character must be encoded as "&quot".
    // "Type=[EntryType]","Path=[Path]","Title=[Title]","Description=[Description]","Thumbnail=[Thumbnail]","Date=[Date]","Duration=[Duration]"|"Type=[entryType]","Path=[Path]","Title=[Title]","Description=[Description]","Thumbnail=[Thumbnail]","Date=[Date]","Duration=[Duration]"|etc...
    //
    // Values:
    // [EntryType]   : 0 = Playable media
    //                 1 = Enter folder
    //                 2 = Append new entries, replace last previous entry (used to trigger the append action).
    //                 3 = Refresh all entries
    // [Path]        : A UTF8 encoded string containing a file path or URL
    // [Title]       : A UTF8 encoded string containing the media's title
    // [Description] : A UTF8 encoded string containing the media's description
    // [Thumbnail]   : A UTF8 encoded string containing the media's thumbnail path or URL
    // [Date]        : A string containing a float number in delphi time encoding representing the publish date and time.
    // [Duration]    : An floating point value representing the media's duration in seconds.
    // [MetaEntry1]  : Displayed in the meta-data's Title area
    // [MetaEntry2]  : Displayed in the meta-data's Date area
    // [MetaEntry3]  : Displayed in the meta-data's Genre/Type area
    // [MetaEntry4]  : Displayed in the meta-data's Overview/Description area
    // [MetaEntry5]  : Displayed in the meta-data's Actors/Media info area
  End;
  PCategoryItemList = ^TCategoryItemList;

Const
  // Settings Registry Path and API Key
  //PluginRegKey               : String = 'Software\VirtuaMedia\ZoomPlayer\MediaLibraryPlugins\RSS Feed';
  RSS_MAX_ENTRIES            : Integer = 5000;

  // Category flags
  catFlagThumbView           : Integer =    1;     // Enable thumb view (disabled = list view)
  catFlagThumbCrop           : Integer =    2;     // Crop media thumbnails to fit in display area (otherwise pad thumbnails)
  catFlagVideoFramesAsThumb  : Integer =    4;     // Grab thumbnails from video frame
  catFlagDarkenThumbBG       : Integer =    8;     // [Darken thumbnail area background], depreciated by "OPNavThumbDarkBG".
  catFlagJukeBox             : Integer =   16;     // Jukebox mode enabled
  catFlagBGFolderIcon        : Integer =   32;     // Draw folder icon if the folder has a thumbnail
  catFlagScrapeParentFolder  : Integer =   64;     // Scrape the parent folder if no meta-data was found for the media file
  catFlagScrapeMediaInFolder : Integer =  128;     // Create folder thumbnails from first media file within the folder (if scraping is disabled or fails)
  catFlagTitleFromMetaData   : Integer =  256;     // Use meta-data title for the thumb's text instead of the file name
  catFlagNoScraping          : Integer =  512;     // Disable all scraping operations for this folder
  catFlagRescrapeModified    : Integer = 1024;     // Rescrape folders if their "modified" date changes
  catFlagTVJukeBoxNoScrape   : Integer = 2048;     // Switched to TV JukeBox list view without having the parent folder scraped first
  catFlag1stMediaFolderThumb : Integer = 4096;     // Instead of scraping for a folder's name, always use the first media file within the folder instead
  catFlagCropCatThumbnail    : Integer = 8192;     // Crop category thumbnails to fit in display area (otherwise pad thumbnails)

  srName                               = 0;
  srExt                                = 1;
  srDate                               = 2;
  srSize                               = 3;
  srPath                               = 4;
  srDuration                           = 5;
  srRandom                             = 6;

  rssExt                     : String  = '.rss';  

// Called by Zoom Player to free any resources allocated in the DLL prior to unloading the DLL.
Procedure FreePlugin; stdcall;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Free Plugin (before)');{$ENDIF}
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Free Plugin (after)');{$ENDIF}
end;


// Called by Zoom Player to init any resources.
function InitPlugin : Bool; stdcall;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Init Plugin (before)');{$ENDIF}
  Result := True;
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Init Plugin (after)');{$ENDIF}
end;


// Called by Zoom Player to verify if the plugin can refresh itself (name/thumbnail).
function CanRefresh : Bool; stdcall;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'CanRefresh (before)');{$ENDIF}
  Result := True;
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'CanRefresh (after)');{$ENDIF}
end;


// Called by Zoom Player to show the refresh the category (name/thumbnail).
Function Refresh(CategoryData : PCategoryPluginRecord) : Integer; stdcall;
var
  sCatInput      : String;
  sCatInputLC    : String;
  sChannelID     : String;
  sCatDataPath   : WideString;
  rssImage       : String;
  rssTitle       : WideString;
  rssDescription : WideString;
  mStream        : TMemoryStream;
  dlStatus       : String;
  dlError        : Integer;
  dlResult       : Boolean;
  iPos           : Integer;
  S              : String;

begin
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Refresh (before)');{$ENDIF}
  Result       := E_FAIL;
  If CategoryData = nil then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Exit on "CategoryData = nil"');{$ENDIF}
    Exit;
  End;

  sCatInput    := StripURLHash(CategoryData^.CategoryInput);
  sCatInputLC  := Lowercase(sCatInput);
  sCatDataPath := UTF8Decode(CategoryData^.DataPath);
  sChannelID   := '';
  CategoryData^.CategoryTitle := '';
  CategoryData^.CategoryThumb := '';
  CategoryData^.Scrapers      := '';
  CategoryData^.TextLines     := 2;
  CategoryData^.SortMode      := srDate;
  CategoryData^.DefaultFlags  := catFlagThumbView or catFlagThumbCrop or catFlagTitleFromMetaData {or catFlagNoScraping}; // Scraping is required for thumbnails

  mStream  := TMemoryStream.Create;
  dlResult := DownloadFileToStream(sCatInput,mStream,dlStatus,dlError,2000);

  If dlResult = False then
  Begin
    // Maybe unknown protocol? try enforcing http
    iPos := Pos('://',sCatInput);
    S := Copy(sCatInputLC,1,iPos-1);
    If (S <> 'http') and (S <> 'https') then
    Begin
      sCatInput := 'http'+Copy(sCatInput,iPos,Length(sCatInput)-(iPos-1));
      dlResult  := DownloadFileToStream(sCatInput,mStream,dlStatus,dlError,2000);
    End;
  End;

  If dlResult = True then
  Begin
    mStream.Position := 0;
    If ParseRSSStream(mStream,rssTitle,rssDescription,rssImage,nil) = True then
    Begin
      CategoryData^.CategoryTitle := PChar(UTF8Encode(rssTitle));
      CategoryData^.CategoryThumb := PChar(rssImage);
      Result := S_OK;
    End;
  End;

  CategoryData^.CategoryID    := PChar(sCatInput);
  mStream.Free;
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Refresh (after)');{$ENDIF}
end;


// Called by Zoom Player to verify if a configuration dialog is available.
// Return True if a dialog exits and False if no configuration dialog exists.
function CanConfigure : Bool; stdcall;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'CanConfigure (before)');{$ENDIF}
  Result := False;
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'CanConfigure (after)');{$ENDIF}
end;


// Called by Zoom Player to show the plugin's configuration dialog.
Procedure Configure(CenterOnWindow : HWND; CategoryID : PChar); stdcall;
{var
  CenterOnRect : TRect;
  tmpInt: Integer;}
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Configure (before)');{$ENDIF}
  {If GetWindowRect(CenterOnWindow,CenterOnRect) = False then
    GetWindowRect(0,CenterOnRect); // Can't find window, center on screen

  ConfigForm := TConfigForm.Create(nil);
  ConfigForm.SetBounds(CenterOnRect.Left+(((CenterOnRect.Right -CenterOnRect.Left)-ConfigForm.Width)  div 2),
                       CenterOnRect.Top +(((CenterOnRect.Bottom-CenterOnRect.Top )-ConfigForm.Height) div 2),ConfigForm.Width,ConfigForm.Height);

  If ConfigForm.ShowModal = mrOK then
  Begin
  End;
  ConfigForm.Free;}
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Configure (after)');{$ENDIF}
end;


Function CreateCategory(CenterOnWindow : HWND; CategoryData : PCategoryPluginRecord) : Integer; stdcall;
var
  sCatInput      : String;
  sCatInputLC    : String;
  sChannelID     : String;
  sCatDataPath   : WideString;
  rssImage       : String;
  rssTitle       : WideString;
  rssDescription : WideString;
  mStream        : TMemoryStream;
  dlStatus       : String;
  dlError        : Integer;
  dlResult       : Boolean;
  iPos           : Integer;
  S              : String;

begin
  // CategoryInput = URL
  // CategoryID    = Parsed category ID returned to the player for later calls to GetList.
  // CategoryThumb = Thumbnail to use for the category
  // TextLines     = Number of text lines to display
  // SortMode      = Sort mode to enable when creating the category (srName .. srRandom)
  // Scrapers      = Return recommended scraper list
  // DefaultFlags  = Default category flags for this category

  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'CreateCategory (before)');{$ENDIF}
  Result       := E_FAIL;
  If CategoryData = nil then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Exit on "CategoryData = nil"');{$ENDIF}
    Exit;
  End;

  sCatInput    := StripURLHash(CategoryData^.CategoryInput);
  sCatInputLC  := Lowercase(sCatInput);
  sCatDataPath := UTF8Decode(CategoryData^.DataPath);
  sChannelID   := '';
  CategoryData^.CategoryTitle := '';
  CategoryData^.CategoryThumb := '';
  CategoryData^.Scrapers      := '';
  CategoryData^.TextLines     := 2;
  CategoryData^.SortMode      := srDate;
  CategoryData^.DefaultFlags  := catFlagThumbView or catFlagThumbCrop or catFlagTitleFromMetaData {or catFlagNoScraping}; // Scraping is required for thumbnails

  mStream  := TMemoryStream.Create;
  dlResult := DownloadFileToStream(sCatInput,mStream,dlStatus,dlError,2000);

  If dlResult = False then
  Begin
    // Maybe unknown protocol? try enforcing http
    iPos := Pos('://',sCatInput);
    S := Copy(sCatInputLC,1,iPos-1);
    If (S <> 'http') and (S <> 'https') then
    Begin
      sCatInput := 'http'+Copy(sCatInput,iPos,Length(sCatInput)-(iPos-1));
      dlResult  := DownloadFileToStream(sCatInput,mStream,dlStatus,dlError,2000);
    End;
  End;

  If dlResult = True then
  Begin
    mStream.Position := 0;
    If ParseRSSStream(mStream,rssTitle,rssDescription,rssImage,nil) = True then
    Begin
      CategoryData^.CategoryTitle := PChar(UTF8Encode(rssTitle));
      CategoryData^.CategoryThumb := PChar(rssImage);
      Result := S_OK;
    End;
  End;

  CategoryData^.CategoryID    := PChar(sCatInput);
  mStream.Free;

  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'CreateCategory, Result : '+IntToHex(Result,8)+' (after)');{$ENDIF}
end;


function DeleteCategory(CenterOnWindow : HWND; CategoryID,DataPath : PChar) : Integer; stdcall;
var
  sDataPath      : WideString;
begin
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'DeleteCategory (before)');{$ENDIF}
  sDataPath := UTF8Decode(DataPath);
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'RSS_Feed ID "'+sDataPath+'"');{$ENDIF}

  // Erase RSS Category cache for this feed
  If WideFileExists(sDataPath+EncodeFileName(CategoryID)+rssExt) = True then
  Begin
    {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Erasing "'+sDataPath+EncodeFileName(CategoryID)+rssExt+'" (before)');{$ENDIF}
    EraseFile(sDataPath+EncodeFileName(CategoryID)+rssExt);
    {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Erasing (after)');{$ENDIF}
  End
  {$IFDEF LOCALTRACE}Else DebugMsgFT(LogInit,'File not found "'+sDataPath+EncodeFileName(CategoryID)+rssExt+'"'){$ENDIF};

  Result := S_OK;
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'DeleteCategory (after)');{$ENDIF}
end;


function SortByDate(Item1, Item2: Pointer) : Integer;
begin
  Result := Trunc((PRSSEntryRecord(Item2)^.rssePublishDate*1000)-(PRSSEntryRecord(Item1)^.rssePublishDate*1000));
  If Result = 0 then Result := WideCompareText(PRSSEntryRecord(Item2)^.rsseURL,PRSSEntryRecord(Item1)^.rsseURL);
end;


Function GetList(CategoryID, CategoryPath, DataPath : PChar; ItemList : PCategoryItemList) : Integer; stdcall;
var
  I              : Integer;
  dlStatus       : String;
  dlError        : Integer;
  sItemList      : WideString;

  mStream        : TMemoryStream;
  mRSSStream     : TMemoryStream;
  rssImage       : String;
  rssTitle       : WideString;
  rssDescription : WideString;
  rssList        : TList;
  sDataPath      : WideString;
  sUTF8          : String;
  //iLen           : Integer;
  dlResult       : Boolean;
  //parseResult    : Boolean;




begin
  // CategoryID   = A unique category identifier, in our case, a YouTube channel's "Channel ID".
  // CategoryPath = Used to the pass a path or parameter, in our case, a YouTube channel's next page Token.
  // ItemList     = Return a list of items and meta-data

  // ItemType :
  // 0 = Playable item
  // 1 = Enter Folder, retrieve new list with additional 'categorypath'.
  // 2 = Append items to list, removing this entry

  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'GetList (before)');{$ENDIF}
  Result             := E_FAIL;

  rssList    := TList.Create;
  mRSSStream := TMemoryStream.Create;
  sDataPath  := UTF8Decode(DataPath);

  {$IFDEF FAKESOURCE}
  mRSSStream.LoadFromFile('d:\showrss.xml');
  dlResult := True;
  {$ELSE}
  dlResult := DownloadFileToStream(CategoryID,mRSSStream,dlStatus,dlError,2500);
  {$ENDIF}


  LoadRSSListFromFile(rssList,sDataPath+EncodeFileName(CategoryID)+rssExt);
  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,IntToStr(rssList.Count)+' entries loaded from cache');{$ENDIF}

  If dlResult = True then
  Begin
    mRSSStream.Position := 0;
    {$IFDEF FEEDDUMP}
    SetLength(sUTF8,mRSSStream.Size);
    mRSSStream.Read(sUTF8[1],mRSSStream.Size);
    DebugMsgFT(LogInit,'RSS Source: '+CRLF+'-----------------------'+CRLF+sUTF8+CRLF+'-----------------------');
    mRSSStream.Position := 0;
    {$ENDIF}

    {$IFDEF LOCALTRACE}parseResult := {$ENDIF}
      ParseRSSStream(mRSSStream,rssTitle,rssDescription,rssImage,rssList);
      
    {$IFDEF LOCALTRACE}
      If parseResult = False then
        DebugMsgFT(LogInit,'Parse failure!');
        DebugMsgFT(LogInit,IntToStr(rssList.Count)+' entries after parsing');
    {$ENDIF}
  End
  {$IFDEF LOCALTRACE}Else DebugMsgFT(LogInit,'Download failed, Status "'+dlStatus+'", Error #'+IntToHex(dlError,8)+' (after)'){$ENDIF};

  If rssList.Count > 0 then
  Begin
    If rssList.Count > RSS_MAX_ENTRIES then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Trimming entries, current count : '+IntToStr(rssList.Count));{$ENDIF}
      While rssList.Count > RSS_MAX_ENTRIES do
      Begin
        Dispose(PRSSEntryRecord(rssList[0]));
        rssList.Delete(0);
      End;
      {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'Trimming complete, current count : '+IntToStr(rssList.Count));{$ENDIF}
    End;

    rssList.Sort(@SortByDate);

    If SaveRSSListToFile(rssList,sDataPath+EncodeFileName(CategoryID)+rssExt) = False then
    Begin
      {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'SaveRSSListToFile returned false!');{$ENDIF}
    End;

    mStream := TMemoryStream.Create;

    For I := 0 to rssList.Count-1 do
    Begin
      If I = 0 then
        //sItemList := RSSrecordToString(PRSSEntryRecord(rssList[I])) else
        //sItemList := sItemList+'|'+RSSrecordToString(PRSSEntryRecord(rssList[I]));
        sUTF8 := UTF8Encode(RSSrecordToString(PRSSEntryRecord(rssList[I]))) else
        sUTF8 := '|'+UTF8Encode(RSSrecordToString(PRSSEntryRecord(rssList[I])));

      mStream.Write(sUTF8[1],Length(sUTF8));
      
      Dispose(PRSSEntryRecord(rssList[I]));
    End;

    // Add a refesh entry with end of string marker "#0".
    sUTF8 := UTF8Encode(sItemList+'|"Type=3",Path="Refresh","MetaEntry5='+rssDescription+'"'+#0);
    mStream.Write(sUTF8[1],Length(sUTF8));
    //iLen  := Length(sUTF8);

    //If iLen < 1024*1024*10 then
    If mStream.Size < 1024*1024*10 then
    Begin
      mStream.Position := 0;
      mStream.Read(ItemList^.catItems^,mStream.Size);
      //Move(sUTF8[1],ItemList^.catItems^,iLen);
      Result := S_OK;
    End
    {$IFDEF LOCALTRACE}Else DebugMsgFT(LogInit,'RSS parsed results larger than the 10mb buffer!!!'){$ENDIF};

    mStream.Free;
  End;

  mRSSStream.Free;
  rssList.Free;

  {$IFDEF LOCALTRACE}DebugMsgFT(LogInit,'GetList (after)');{$ENDIF}
end;


// The string to display for the users when asking for input, in our case, a youtube channel URL
function GetInputID : PChar; stdcall;
begin
  Result := 'RSS URL :';
end;


// The string to display for the users when asking for input, in our case, a youtube channel URL
function RequireTitle : Bool; stdcall;
begin
  Result := False;
end;


function RequireInput : Bool; stdcall;
begin
  Result := False;
end;


exports
   InitPlugin,
   FreePlugin,
   CanRefresh,
   Refresh,
   CanConfigure,
   Configure,
   GetList,
   CreateCategory,
   DeleteCategory,
   RequireTitle,
   RequireInput,
   GetInputID;


begin
  // Required to notify the memory manager that this DLL is being called from a multi-threaded application!
  IsMultiThread := True;
end.


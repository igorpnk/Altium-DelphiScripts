{..............................................................................
   NetColours.pas
   SchDoc current sheet

   A crazy-as method (must be a better way) to find ILine (& Net) from Sch-Wire & reverse.

   ColourANetInDoc Can run with pre-selected objects (netitems) or interactively..
   ColourNetsInDoc preset colours & width in code & run over Doc.

   Colours & widths applied are hard coded.
   Only Sch_Wire (ILine) objects supported.

BL Miller
15/09/2018  v0.10
17/03/2020  v0.20 Added Colour specified NetName in current Doc.

..............................................................................}

{..............................................................................}

Var
    WS           : IWorkspace;
    Rpt          : TStringList;
    NetsData     : TStringList;
    NetList      : TObjectList;
    Preferences  : ISch_Preferences;
    Units        : TUnits;
    UnitsSys     : TUnitSystem;

Procedure GenerateReport(const Filename : WideString, const Display :boolean);
Var
    Prj      : IProject;
    Document : IServerDocument;
    Filepath : WideString;

Begin
    WS  := GetWorkspace;
    If WS <> Nil Then
    begin
       Prj := WS.DM_FocusedProject;
       If Prj <> Nil Then
          Filepath := ExtractFilePath(Prj.DM_ProjectFullPath)
       else
          Filepath := ExtractFilePath(WS.DM_FocusedDocument.DM_ProjectFullPath);
    end;

    If length(Filepath) < 5 then Filepath := 'c:\temp\';
    Filepath := Filepath + Filename;
    Rpt.SaveToFile(Filepath);

    Document := Client.OpenDocument('Text',Filepath);
    if display and (Document <> Nil) Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
End;

function FetchNetsFromDoc(ADoc : IDocument) : TObjectList;
var
    J         : Integer;
    ANet      : INet;

begin
    Result := TObjectList.Create;
    // need the physical document for net information...
    for J := 0 to (ADoc.DM_NetCount - 1) Do
    begin
        ANet := ADoc.DM_Nets(J);
        Result.Add(ANet);
    end;
end;

function FindMatchingNetItem(Doc : IDocument, APrim : ISch_GraphicalObject) : INetItem;
var
    ALine      : ILine;
    ANet       : INet;
    I, J       : integer;
    L1, L2, L3 : TLocation;
    SDS        : WideString;

begin
    Result := nil;
    for I := 0 to  (NetList.Count - 1) do
    begin
        ANet := NetList.Items(I);
        ANet.DM_NetName;
    case APrim.ObjectID of
    eWire :
        begin
            APrim.UniqueId ;                 // HYBLJPOB
            APrim.Handle ;                   // AKTRVOOQ\HYBLJPOB
            L1 := APrim.Location;
            L2 := L1;
            if APrim.VerticesCount > 0 then L1 := APrim.Vertex(1);
            if APrim.VerticesCount > 1 then L2 := APrim.Vertex(2);
            if (L2.x < L1.x) or ((L2.y < L1.y) and (L2.x = L1.x)) then
            begin
                L3 := L1;
                L1 := L2;
                L2 := L3;
            end;

        // eImperial 0  eMM 1  eMetric 1 ,  eDXP 4

            SDS := '(' + CoordUnitToStringNoUnit(L1.x, Units) + ',' +  CoordUnitToStringNoUnit(L1.y, Units);
            SDS := SDS + ') To ('+ CoordUnitToStringNoUnit(L2.x, Units) + ',' +  CoordUnitToStringNoUnit(L2.y, Units) + ')';

            for J := 0 to (ANet.DM_LineCount - 1) do
            begin
                ALine := ANet.DM_Lines(J);
                ALine.DM_NetIndex_Sheet ;

                if SDS = ALine.DM_ShortDescriptorString  then       // '(740,940) To (820,940)'
                begin
                    Result := ALine;
                    break;
                end;
            end;
        end;
    end;  // case
    end;  // for I
end;

function FindMatchingSchPrim(Doc : IDocument, ANetItem : INetItem) : ISch_GraphicalObject;
var
    CurrentSch : ISch_Document;
    APrim      : ISch_GraphicalObject;
    Iterator   : ISch_Iterator;
    ALine    : ILine;
    ANet     : INet;
    AWire    : ISch_Wire;
    I, J       : integer;
    L1, L2, L3 : TLocation;
    SDS        : WideString;

begin
    Result := nil;
    Rpt.Add(ANetItem.DM_ShortDescriptorString);

    CurrentSch := SchServer.GetSchDocumentByPath(Doc.DM_FullPath);
    Iterator := CurrentSch.SchIterator_Create;
    Iterator.AddFilter_ObjectSet(MkSet(eLine, eWire, eBus, ePort));

    APrim := Iterator.FirstSchObject;

    while APrim <> nil  do
    begin

        case APrim.ObjectId of
            eWire :                      // eWire
            begin
                ALine := ANetItem;

                L1 := APrim.Location;   // is midpoint of line ?? test this ??
                L2 := L1;
                APrim.GetState_DescriptionString;     //  eWire=  'Wire' ; eLine= 'Line(x1,y1)(x2,y2)'
                if APrim.VerticesCount > 0 then L1 := APrim.Vertex(1);
                if APrim.VerticesCount > 1 then L2 := APrim.Vertex(2);

                if (L2.x < L1.x) or ((L2.y < L1.y) and (L2.x = L1.x)) then
                begin
                    L3 := L1;
                    L1 := L2;
                    L2 := L3;
                end;

        //   eImperial 0  eMM 1  eMetric 1 ,  eDXP 4
                SDS := '(' + CoordUnitToStringNoUnit(L1.x, Units) + ',' +  CoordUnitToStringNoUnit(L1.y, Units);
                SDS := SDS + ') To ('+ CoordUnitToStringNoUnit(L2.x, Units) + ',' +  CoordUnitToStringNoUnit(L2.y, Units) + ')';

                Rpt.Add('SDS ' + SDS);
                if SDS = ALine.DM_ShortDescriptorString  then       // '(740,940) To (820,940)'
                begin
                    Rpt.Add('Prim Loc ' + IntToStr(APrim.Location.x) + ' ' + IntToStr(APrim.Location.y) + '  Line DM_L_ ' + IntToStr(ALine.DM_LX) + ' ' + IntToStr(ALine.DM_LY) );
                    Result := APrim;
                    break;
                end;
            end;
        end;  // case

        APrim := Iterator.NextSchObject;
    end;  // while
    CurrentSch.SchIterator_Destroy(Iterator);
end;


Procedure MatchSameNetAndType(Doc : IDocument, NetObjList : TObjectList);
Var
    CurrentSch    : ISch_Document;
    ANet          : INet;
    APrim         : ISch_GraphicalObject;
    ANetItem      : INetItem;
    ALine         : ILine;
    AWire         : ISch_Wire;
    APort         : ISch_Port;
    ASheetEntry   : ISch_SheetEntry;
    ANetLabel     : ISch_NetLabel;
    APowerPort    : ISch_Powerobject;
    ABusEntry     : ISch_BusEntry;
    ACrossSheet   : ISch_CrossSheetConnector;
    AHarnEntry    : ISch_HarnessEntry;
    AParameterSet : ISch_ParameterSet;
    I             : integer;

Begin
    NetList   := FetchNetsFromDoc(Doc);

 //   INet.DM_Lines(0).DM_NetIndex_Sheet;

    for I := 0 to (NetObjList.Count - 1) do
    begin
        APrim := NetObjList.Items(I);

        case APrim.ObjectID of
        eWire :
        begin
            AWire := APrim;
            ANetItem := FindMatchingNetItem(Doc, AWire);

            AWire.GetState_IdentifierString;
            AWire.GetState_DescriptionString ;
            AWire.UniqueId ;
            AWire.Color := StringToColor('clBlue');
        end;
        ePort :
            begin
            APort := APrim;
            APort.Color     := StringToColor('clBlue');
            APort.AreaColor := StringToColor('clRed');
            APort.TextColor := StringToColor('clBlack');
            APort.FontID    := SchServer.FontManager.GetFontID(10,0,False,False,False,False,'Verdena');

            end;
        eBusEntry :
            begin
            ABusEntry := APrim;
            end;
        eSheetEntry :
            begin
            ASheetEntry := APrim;
            ASheetEntry.TextFontID := SchServer.FontManager.GetFontID(12,0,False,False,False,False,'Verdena');
            ASheetEntry.TextStyle;
            ASheetEntry.TextColor  := StringToColor('clBlue');    // $D8FFFF;    // light yellow
            ASheetEntry.GraphicallyInvalidate;     //UniqueId ;
            end;
        eNetLabel :
            begin
            ANetLabel := APrim;
            ANetLabel.Color := StringToColor('clRed');
            ANetLabel.AreaColor := StringToColor('clBlue');
            end;
        eHarnessEntry :
            begin
            AHarnEntry := APrim;
            AHarnEntry.TextFontID :=SchServer.FontManager.GetFontID(12,0,False,False,False,False,'Verdena');
            AHarnEntry.TextColor := StringToColor('clBlue');
            AHarnEntry.GraphicallyInvalidate;
            end;
        eCrossSheetConnector :
            begin
            ACrossSheet := APrim;
            ACrossSheet.FontID := SchServer.FontManager.GetFontID(12,0,False,False,False,False,'Verdena');
            ACrosssheet.Color := StringToColor('clBlue');
            ACrossSheet.GraphicallyInvalidate;
            end;
        eParameterSet :
            begin
            AParameterSet := APrim;
          //  AParameterSet.Name.TextFontID := SchServer.FontManager.GetFontID(12,0,False,False,False,False,'Verdena');
          //  AParameterSet.Name.TextColor := StringToColor('clGreen');
            AParameterSet.GraphicallyInvalidate;
            AParameterSet.Orientation   ;
            AParameterSet.Style   ;
            end;
//        else
        end;
    end;
End;

Function FindSelectedNetItems(Doc : IDocument) : TObjectList;
Var
    CurrentSch   : ISch_Document;
    Iterator     : ISch_Iterator;
    NetObj       : ISch_Object;
    ASheetEntry  : ISch_SheetEntry;

Begin
    Result :=TObjectList.Create;

    CurrentSch := SchServer.GetSchDocumentByPath(Doc.DM_FullPath);

    Iterator := CurrentSch.SchIterator_Create;
    // Problem: eWire has no Net property but eLine is not selected from clicking a net
    Iterator.AddFilter_ObjectSet(MkSet(eParameterSet, ePin, eWire, eJunction, ePort, eSheetEntry, eBusEntry, eHarnessEntry, ePowerObject, eNetLabel, eCrossSheetConnector));
    Try
        NetObj := Iterator.FirstSchObject;
        While (NetObj <> Nil) Do
        Begin
            if NetObj.Selection = True then
                Result.Add(NetObj);          // found selected net item !

            NetObj := Iterator.NextSchObject;
        End;
    Finally
        CurrentSch.SchIterator_Destroy(Iterator);
    End;
End;


function ColourNet(Doc : IDocument, NetName : WideString, const APrimId : integer, NColour : TColor, WWidth :TSize) : boolean;
var
    ANet   : INet;
    ALine  : ILine;
    AWire  : ISch_Wire;
    I, J   : integer;
    ValidWidth : TSet;

begin
    ValidWidth := MkSet(eZeroSize, eSmall, eMedium, eLarge);
    if Not InSet(WWidth, ValidWidth) then WWidth := eMedium;

    for I := 0 to  (Doc.DM_NetCount - 1) do
    begin
        ANet := Doc.DM_Nets(I);
        ANet.DM_ObjectKindString;

        if ANet.DM_NetName = NetName then
        begin
            case APrimId of
            eWire :
                begin
                    for J := 0 to (ANet.DM_LineCount - 1) do
                    begin
                        ALine := ANet.DM_Lines(J);
                        ALine.DM_NetIndex_Sheet;
                        AWire := FindMatchingSchPrim(Doc, ALine);
                        if AWire <> nil then
                        begin
                            AWire.Color := NColour;
                            AWire.LineWidth := WWidth;
                        end;
                    end;
                end;
            end;  // case
        end;  // if netname
    end;  // for I
end;


Procedure ColourNetsInDoc();
var
    Doc          : IDocument;
    CurrentSch   : ISch_Document;

begin
    WS  := GetWorkspace;
    If WS  = Nil Then Exit;
    Doc := WS.DM_FocusedDocument;
    If Doc.DM_DocumentKind <>  cDocKind_Sch Then Exit;

    If SchServer = Nil Then Exit;
    CurrentSch := SchServer.GetSchDocumentByPath(Doc.DM_FullPath);
    If CurrentSch = Nil Then
        CurrentSch := SchServer.LoadSchDocumentByPath(Doc.DM_FullPath);
    If CurrentSch = Nil Then Exit;

    Doc.DM_Compile;
//    Prj.DM_Compile;

    Rpt := TStringList.Create;
    Rpt.Add('ColourNets');

    Preferences := SchServer.Preferences;
    Units    := Preferences.DefaultDisplayUnit;
    UnitsSys := Preferences.DefaultUnitSystem;
    UnitsSys := CurrentSch.UnitSystem;

    NetList   := FetchNetsFromDoc(Doc);

{    TSize eZeroSize,
eSmall,
eMedium,
eLarge
}
    ColourNet(Doc, 'GND', eWire, StringToColor('clGreen'), eLarge);
    ColourNet(Doc, 'VDD', eWire, StringToColor('clRed'), eLarge);

    GenerateReport('ColourNet.txt', true);
end;

Procedure ColourANetInDoc();
Var
    Prj          : IProject;
    Doc          : IDocument;
    CurrentSch   : ISch_Document;
    ANetItem     : INetItem;
    NetObjList   : TObjectList;
    ALocation    : TLocation;
    PreSelect    : Boolean;
    AHitTest     : ISch_HitTest;
    AHitTestMode : THitTestMode;
    APrim        : ISch_GraphicalObject;
    I            : Integer;

Begin
    WS  := GetWorkspace;
    If WS  = Nil Then Exit;
    Prj := WS.DM_FocusedProject;
    If Prj = Nil Then Exit;

// do a compile so the logical documents get expanded into physical documents.
    Prj.DM_Compile;

    Doc := WS.DM_FocusedDocument;
    If Doc.DM_DocumentKind <>  cDocKind_Sch Then Exit;

    If SchServer = Nil Then Exit;
    CurrentSch := SchServer.GetSchDocumentByPath(Doc.DM_FullPath);
    // if you have not double clicked on Doc it may be open but not loaded.
    If CurrentSch = Nil Then
        CurrentSch := SchServer.LoadSchDocumentByPath(Doc.DM_FullPath);
    If CurrentSch = Nil Then Exit;

    Preferences := Schserver.Preferences;
    Units    := Preferences.DefaultDisplayUnit;
    UnitsSys := Preferences.DefaultUnitSystem;
    UnitsSys := CurrentSch.UnitSystem;

    NetObjList := FindSelectedNetItems(Doc);

    If NetObjList.Count = 0 then
    begin
        ALocation :=  CurrentSch.Location;    //   Point(220, 200);
        CurrentSch.ChooseLocationInteractively(ALocation,'Please select net object');
        AHitTestMode := eHitTest_AllObjects;
        AHitTest := CurrentSch.CreateHitTest(AHitTestMode,ALocation);
        If AHitTest <> Nil then
        begin
            For I := 0 to (AHitTest.HitTestCount - 1) Do
            Begin
               APrim := AHitTest.HitObject[I];        //ISch_GraphicalObject
               APrim.UniqueId ;
               NetObjList.Add(APrim);
            end;
        end;
    end;

    If NetObjList.Count > 0 then
        MatchSameNetAndType(Doc, NetObjList);

End;


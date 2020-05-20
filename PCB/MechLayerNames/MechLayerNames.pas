{ MechLayerNames.pas                                                              }
{ Summary   Used to export/import mech layer info to/from a text *.ini file.      }
{           Works on PcbDoc & PcbLib files.                                       }
{           Mechanical layer Names, Colours and MechanicalPairs can be            }
{           exported/imported to another PcbDoc/PcbLib file                       }
{                                                                                 }
{ Created by:    Petar Perisin                                                    }
{
 Modified by : B. Miller
 Date        Ver  Comment
 03/07/2017  : mod to fix layer names output, why was import okay ??
 23/02/2018  : added MechLayer Pairs & colours, still loads old ini files.
 18/08/2019  : Layer colours above eMech16 are all cBlack so ignore.
 28/08/2019  : Try improve import default filepath.
 12/09/2019  : Layer tab display refresh without "flashing" & fix colours for all layers.
 18/09/2019  : Versioncheck & set max mech layers for AD19 & later
 19/09/2019 1.1  Export: Limit continuous sequential layer export listing to below AllLayerDataMax
                 Import: test the Layer Section Key exists.
 02/10/2019 1.2  AD19 mechlayer Kind with legacy conversion back to layer pair(s)
 15/10/2019 1.3  Support all (known) mech layer kinds & component layer pairs.
 16/02/2020 1.4  Add proc for AD ver >= 19; Convert MechLayer Kinds to Legacy mech style.

Notes: Legacy fallback for AD17/18; drop ML "kind" but retain pairings & names etc.

..................................................................................}
const
    NoColour          = 'ncol';
    AD19VersionMajor  = 19;
    AD17MaxMechLayers = 32;       // scripting API has broken consts from TV6_Layer
    AD19MaxMechLayers = 1024;
    AllLayerDataMax   = 16;       // after this mech layer index only report the actual active layers.
    NoMechLayerKind   = 0;        // enum const does not exist for AD17/18
    ctTop             = 'Top';    // text used denote mech layer kind pairs.
    ctBottom          = 'Bottom';

var
    Board          : IPCB_Board;
    LayerStack     : IPCB_LayerStack_V7;
    LayerObj_V7    : IPCB_LayerObject_V7;
    MechLayer      : IPCB_MechanicalLayer;
    MechLayerKind  : TMechanicalLayerKind;
    MLayerKindStr  : WideString;
    MechPairs      : IPCB_MechanicalLayerPairs;
    VerMajor      : WideString;
    MaxMechLayers : integer;
    FileName      : String;
    INIFile       : TIniFile;
    Flag          : Integer;
    ML1, ML2      : integer;
    i, j          : Integer;
    LegacyMLS     : boolean;

{.................................................................................}
function Version(const dummy : boolean) : TStringList;
begin
    Result               := TStringList.Create;
    Result.Delimiter     := '.';
    Result.Duplicates    := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;

function LayerKindToStr(LK : TMechanicalLayerKind) : WideString;
begin
    case LK of
    NoMechLayerKind : Result := 'Not Set';            // single
    1               : Result := 'Assembly Top';
    2               : Result := 'Assembly Bottom';
    3               : Result := 'Assembly Notes';     // single
    4               : Result := 'Board';
    5               : Result := 'Coating Top';
    6               : Result := 'Coating Bottom';
    7               : Result := 'Component Center Top';
    8               : Result := 'Component Center Bottom';
    9               : Result := 'Component Outline Top';
    10              : Result := 'Component Outline Bottom';
    11              : Result := 'Courtyard Top';
    12              : Result := 'Courtyard Bottom';
    13              : Result := 'Designator Top';
    14              : Result := 'Designator Bottom';
    15              : Result := 'Dimensions';         // single
    16              : Result := 'Dimensions Top';
    17              : Result := 'Dimensions Bottom';
    18              : Result := 'Fab Notes';         // single
    19              : Result := 'Glue Points Top';
    20              : Result := 'Glue Points Bottom';
    21              : Result := 'Gold Plating Top';
    22              : Result := 'Gold Plating Bottom';
    23              : Result := 'Value Top';
    24              : Result := 'Value Bottom';
    25              : Result := 'V Cut';             // single
    26              : Result := '3D Body Top';
    27              : Result := '3D Body Bottom';
    28              : Result := 'Route Tool Path';   // single
    29              : Result := 'Sheet';             // single
    else              Result := 'Unknown'
    end;
end;

function LayerStrToKind(LKS : WideString) : TMechanicalLayerKind;
var
    I : integer;
begin
    Result := -1;
    for I := 0 to 30 do
    begin
         if LayerKindToStr(I) = LKS then
         begin
             Result := I;
             break;
         end;
    end;
end;

function IsMechLayerKindPair(LKS : WideString, var RootKind : WideString) : boolean;
// RootKind : basename of layer kind (Assembly, Coating, Courtyard etc)
var
    WPos : integer;
begin
    Result := false;
    RootKind := LKS;
    WPos := AnsiPos(ctTop,LKS);
    if WPos > 2 then
    begin
        Result := true;
        SetLength(RootKind, WPos - 2);
    end;
    WPos := AnsiPos(ctBottom,LKS);
    if WPos > 2 then
    begin
        Result := true;
        SetLength(RootKind, WPos - 2);
    end;
end;

Procedure ExportMechLayerInfo;
var
    SaveDialog  : TSaveDialog;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then exit;

    VerMajor := Version(true).Strings(0);

    MaxMechLayers := AD17MaxMechLayers;
    LegacyMLS     := true;
    MechLayerKind := NoMechLayerKind;
    if (VerMajor >= AD19VersionMajor) then
    begin
        LegacyMLS     := false;
        MaxMechLayers := AD19MaxMechLayers;
    end;

    SaveDialog        := TSaveDialog.Create(Application);
    SaveDialog.Title  := 'Save Mech Layer Names to *.ini file';
    SaveDialog.Filter := 'INI file (*.ini)|*.ini';
    FileName := ExtractFilePath(Board.FileName);
    SaveDialog.FileName := ChangeFileExt(FileName, '');

    Flag := SaveDialog.Execute;
    if (Flag = 0) then exit;

    // Get file & set extension
    FileName := SaveDialog.FileName;
    FileName := ChangeFileExt(FileName, '.ini');
    IniFile := TIniFile.Create(FileName);

    BeginHourGlass(crHourGlass);

    LayerStack := Board.LayerStack_V7;
    MechPairs  := Board.MechanicalPairs;

    for i := 1 to MaxMechLayers do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        MechLayer := LayerStack.LayerObject_V7[ML1];

        if (i <= AllLayerDataMax) or MechLayer.MechanicalLayerEnabled then
        begin
            if not LegacyMLS then MechLayerKind := MechLayer.Kind;
            MLayerKindStr := LayerKindToStr(MechLayerKind);

            IniFile.WriteString('MechLayer' + IntToStr(i), 'Name',    Board.LayerName(ML1) );       // MechLayer.Name);
            IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'Enabled', MechLayer.MechanicalLayerEnabled);
            IniFile.WriteString('MechLayer' + IntToStr(i), 'Kind',    MLayerKindStr);
            IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'Show',    MechLayer.IsDisplayed[Board]);
            IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'Sheet',   MechLayer.LinkToSheet);
            IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'SLM',     MechLayer.DisplayInSingleLayerMode);
            IniFile.WriteString('MechLayer' + IntToStr(i), 'Color',   ColorToString(Board.LayerColor[ML1]) );

// if layer has valid "Kind", STILL need (our) explicit pairing to be set.
            for j := 1 to MaxMechLayers do
            begin
                ML2 := LayerUtils.MechanicalLayer(j);
                if MechPairs.PairDefined(ML1, ML2) then
                    IniFile.WriteString('MechLayer' + IntToStr(i), 'Pair', Board.LayerName(ML2) );
            end;
        end;
    end;
    IniFile.Free;
    EndHourGlass;
end;


Procedure ImportMechLayerInfo;
var
    PCBSysOpts     : IPCB_SystemOptions;
    OpenDialog     : TOpenDialog;
    MechLayer2     : IPCB_MechanicalLayer;
    MPairLayer     : WideString;
    MechLayerKind2 : TMechanicalLayerKind;
    MLayerKindStr2 : WideString;
    MLKindRoot     : WideString;
    MLKindRoot2    : WideString;
    LColour        : TColor;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then exit;
    PCBSysOpts := PCBServer.SystemOptions;
    If PCBSysOpts = Nil Then exit;

    VerMajor := Version(true).Strings(0);

    MaxMechLayers := AD17MaxMechLayers;
    LegacyMLS     := true;
    MechLayerKind := NoMechLayerKind;
    if (VerMajor >= AD19VersionMajor) then
    begin
        MaxMechLayers := AD19MaxMechLayers;
        LegacyMLS     := false;
    end;

    OpenDialog        := TOpenDialog.Create(Application);
    OpenDialog.Title  := 'Import Mech Layer Names from *.ini file';
    OpenDialog.Filter := 'INI file (*.ini)|*.ini';
//    OpenDialog.InitialDir := ExtractFilePath(Board.FileName);
    OpenDialog.FileName := '';
    Flag := OpenDialog.Execute;
    if (Flag = 0) then exit;

    FileName := OpenDialog.FileName;
    IniFile := TIniFile.Create(FileName);

    BeginHourGlass(crHourGlass);
    LayerStack := Board.LayerStack_V7;
    MechPairs  := Board.MechanicalPairs;

    for i := 1 To MaxMechLayers do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        MechLayer := LayerStack.LayerObject_V7[ML1];

        if IniFile.SectionExists('MechLayer' + IntToStr(i)) then
        begin
            MechLayer.Name := IniFile.ReadString('MechLayer' + IntToStr(i), 'Name', 'eMech' + IntToStr(i));

//    allow turn Off -> ON only, default Off for missing entries
            If Not MechLayer.MechanicalLayerEnabled then
                MechLayer.MechanicalLayerEnabled := IniFile.ReadBool('MechLayer' + IntToStr(i), 'Enabled', False);

            MLayerKindStr                      := IniFile.ReadString('MechLayer' + IntToStr(i), 'Kind',  LayerKindToStr(NoMechLayerKind) );
            MPairLayer                         := IniFile.ReadString('MechLayer' + IntToStr(i), 'Pair',  '');
            MechLayer.LinkToSheet              := IniFile.ReadBool  ('MechLayer' + IntToStr(i), 'Sheet', False);
            MechLayer.DisplayInSingleLayerMode := IniFile.ReadBool  ('MechLayer' + IntToStr(i), 'SLM',   False);
            MechLayer.IsDisplayed[Board]       := IniFile.ReadBool  ('MechLayer' + IntToStr(i), 'Show',  True);
            LColour                            := IniFile.ReadString('MechLayer' + IntToStr(i), 'Color', NoColour);
            if LColour <> NoColour then
                PCBSysOpts.LayerColors(ML1) := StringToColor( LColour);

            MechLayerKind := LayerStrToKind(MLayerKindStr);
//    new "kind" pairs are treated individually by kind but are still a Pair
            if not LegacyMLS then
                 MechLayer.Kind  := MechLayerKind;

//    remove existing mechpairs & add new ones.
//    potentially new layer names in this file are of mech pair; only check parsed ones.
            for j := 1 to (i - 1) do
            begin
                ML2            := LayerUtils.MechanicalLayer(j);
                MechLayer2     := LayerStack.LayerObject_V7(ML2);
                MLayerKindStr2 := IniFile.ReadString('MechLayer' + IntToStr(j), 'Kind',  IntToStr(NoMechLayerKind) );
                MechLayerKind2 := LayerStrToKind(MLayerKindStr2);

//        remove pair including backwards ones !
                if MechPairs.PairDefined(ML2, ML1) then
                    MechPairs.RemovePair(ML2, ML1);
                if MechPairs.PairDefined(ML1, ML2) then
                    MechPairs.RemovePair(ML1, ML2);

                if (MPairLayer = MechLayer2.Name) and not MechPairs.PairDefined(ML2, ML1) then
                    MechPairs.AddPair(ML2, ML1);

//  just in case a "Kind" pair does not have "Pair" set..
                if LegacyMLS and (not MechPairs.PairDefined(ML2, ML1) ) then
                begin
                    MLKindRoot  := '';       // root basename of layer kind (Assembly, Coating, Courtyard etc)
                    MLKindRoot2 := '';
                    if IsMechLayerKindPair(MLayerKindStr,  MLKindRoot) and
                       IsMechLayerKindPair(MLayerKindStr2, MLKindRoot2) then
                        if (MLKindRoot = MLKindRoot2) and (MLKindRoot <> '') then
                            MechPairs.AddPair(ML2, ML1);
                end;
            end;

        end; // section exists
    end;

    EndHourGlass;
    IniFile.Free;
    Board.ViewManager_UpdateLayerTabs;
    ShowInfo('Mechanical Layer Names & Colours (& pairs) updated.');
end;

Procedure ConvertMechLayerKindToLegacy;
var
    MechLayer2     : IPCB_MechanicalLayer;
    MPairLayer     : WideString;
    MechLayerKind2 : TMechanicalLayerKind;
    MLayerKindStr  : WideString;
    MLayerKindStr2 : WideString;
    MLayerName     : WideString;
    MLKindRoot     : WideString;
    MLKindRoot2    : WideString;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then exit;

    VerMajor := Version(true).Strings(0);

    MaxMechLayers := AD17MaxMechLayers;
    LegacyMLS     := true;
    MechLayerKind := NoMechLayerKind;
    if (VerMajor >= AD19VersionMajor) then
    begin
        MaxMechLayers := AD19MaxMechLayers;
        LegacyMLS     := false;
    end else
    begin
        ShowMessage('Requires AD19 or later to convert ');
        exit;
    end; 

    LayerStack := Board.LayerStack_V7;
    MechPairs  := Board.MechanicalPairs;

    for i := 1 To MaxMechLayers do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        MechLayer := LayerStack.LayerObject_V7[ML1];

//  existing
        MLayerName    := MechLayer.Name;
        MechLayerKind := MechLayer.Kind;
        MLayerKindStr := LayerKindToStr(MechLayerKind);

//        If MechLayer.MechanicalLayerEnabled then

        if not (MechLayerKind = NoMechLayerKind) then
        begin
            MechLayerKind := NoMechLayerKind;       //  'Not Set'
//     new "kind" pairs are treated individually by kind but are still a Pair
            MechLayer.Kind  := MechLayerKind;


//    remove existing mechpairs & add new ones.
//    potentially new layer names in this file are of mech pair; only check parsed ones.
            for j := 1 to (i - 1) do
            begin
                ML2            := LayerUtils.MechanicalLayer(j);
                MechLayer2     := LayerStack.LayerObject_V7(ML2);
                MLayerKindStr2 := LayerKindToStr(MechLayer2.Kind);
                MechLayerKind2 := LayerStrToKind(MLayerKindStr2);

//  just in case a "Kind" pair does not have "Pair" set..
                if not MechPairs.PairDefined(ML2, ML1) then
                begin
                    MLKindRoot  := '';       // root basename of layer kind (Assembly, Coating, Courtyard etc)
                    MLKindRoot2 := '';
                    if IsMechLayerKindPair(MLayerKindStr,  MLKindRoot) and
                       IsMechLayerKindPair(MLayerKindStr2, MLKindRoot2) then
                        if (MLKindRoot = MLKindRoot2) and (MLKindRoot <> '') then
                            MechPairs.AddPair(ML2, ML1);
                end;
            end;
        end; // if MechLayerKind
    end;

    Board.ViewManager_UpdateLayerTabs;
    ShowInfo('Converted Mechanical Layer Kinds To Legacy ..');
end;

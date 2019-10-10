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
 02/10/2019 1.2  AD19 mechlayer Kind with legacy conversion back to pair


Can already iterate 1 to 64 mech layers in AD17! (see MechLayerNames-test.pas)
 tbd: will it crash?

..................................................................................}
const
    NoColour          = 'ncol';
    AD19VersionMajor  = 19;
    AD17MaxMechLayers = 32;     // scripting API has broken consts from TV6_Layer
    AD19MaxMechLayers = 1024;
    AllLayerDataMax   = 16;     // after this mech layer index only report the actual active layers.
    NoMechLayerKind   = 0;      // enum const does not exist for AD17/18

var
    Board          : IPCB_Board;
    LayerStack     : IPCB_LayerStack_V7;
    LayerObj_V7    : IPCB_LayerObject_V7;
    MechLayer      : IPCB_MechanicalLayer;
    MechLayerKind  : TMechanicalKind;
    MLayerKindStr  : WideString;
    MechLayerKind2 : TMechanicalKind;
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
    Result := TStringList.Create;
    Result.Delimiter := '.';
    Result.Duplicates := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;

function LayerKindToStr(LK : TMechanicalKind) : WideString;
begin
    case LK of
    NoMechLayerKind : Result := 'Not Set';
    1               : Result := 'Assembly';
    2               : Result := 'Courtyard';
    else              Result := 'Unknown'
    end;
end;
function LayerStrToKind(LKS : WideString) : TMechanicalKind;
var
    I : integer;
begin
    Result := -1;
    for I := 0 to 10 do
    begin
         if LayerKindToStr(I) = LKS then
         begin
             Result := I;
             break;
         end;
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

// if layer has valid "Kind" do not need (our) explicit pairing.
            if (MechLayerKind <= NoMechLayerKind) then
            begin
                for j := 1 to MaxMechLayers do
                begin
                    ML2 := LayerUtils.MechanicalLayer(j);
                    if MechPairs.PairDefined(ML1, ML2) then
                        IniFile.WriteString('MechLayer' + IntToStr(i), 'Pair', Board.LayerName(ML2) );
                end;
            end;
        end;
    end;
    IniFile.Free;
    EndHourGlass;
end;


Procedure ImportMechLayerInfo;
var
    PCBSysOpts : IPCB_SystemOptions;
    OpenDialog : TOpenDialog;
    MechLayer2 : IPCB_MechanicalLayer;
    MPairLayer : String;
    LColour    : TColor;
    LKind      : TLayerKind;

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

//    remove existing mechpairs & add new ones.
//    potentially new layer names in this file are of mech pair; only check parsed ones.
            for j := 1 to (i - 1) do
            begin
                ML2            := LayerUtils.MechanicalLayer(j);
                MechLayer2     := LayerStack.LayerObject_V7(ML2);
                MechLayerKind2 := LayerStrToKind( IniFile.ReadString('MechLayer' + IntToStr(j), 'Kind',  IntToStr(NoMechLayerKind) ) );

//        remove pair including backwards ones !
                if MechPairs.PairDefined(ML2, ML1) then
                    MechPairs.RemovePair(ML2, ML1);
                if MechPairs.PairDefined(ML1, ML2) then
                    MechPairs.RemovePair(ML1, ML2);
                if not LegacyMLS then
                begin
                    MechLayer.Kind  := NoMechLayerKind;
                    MechLayer2.Kind := NoMechLayerKind;
                end;

//        add pairs back if "Pair" but not if valid "Kind"
                if (MechLayerKind <= NoMechLayerKind) then
                begin
                    if (MPairLayer = MechLayer2.Name) and not MechPairs.PairDefined(ML2, ML1) then
                        MechPairs.AddPair(ML2, ML1);
                end
//        legacy convert Kind to pairs if Kind is valid
                else
                begin
                    if LegacyMLS then
                    begin
                        if (MechLayerKind = MechLayerKind2) and not MechPairs.PairDefined(ML2, ML1) then
                            MechPairs.AddPair(ML2, ML1);
                    end
                    else
                    begin
                        MechLayer.Kind  := MechLayerKind;
                        MechLayer2.Kind := MechLayerKind;
                    end;
                end;
            end;

        end; // section exists
    end;

    EndHourGlass;
    IniFile.Free;
    Board.ViewManager_UpdateLayerTabs;
    ShowInfo('Mechanical Layer Names & Colours (& pairs) updated.');
end;

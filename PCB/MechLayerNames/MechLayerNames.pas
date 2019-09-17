{ MechLayerNames.pas                                                              }
{ Summary   Used to export/import mech layer info to/from a text *.ini file.      }
{           Works on PcbDoc & PcbLib files.                                       }
{           Mechanical layer Names, Colours and MechanicalPairs can be            }
{           exported/imported to another PcbDoc/PcbLib file                       }
{                                                                                 }
{ Created by:    Petar Perisin                                                    }
{
 Modified by : B. Miller
 03/07/2017  : mod to fix layer names output, why was import okay ??
 23/02/2018  : added MechLayer Pairs & colours, still loads old ini files.
 18/08/2019  : Layer colours above eMech16 are all cBlack so ignore.
 28/08/2019  : Try improve import default filepath.
 12/09/2019  : Layer tab display refresh without "flashing" & fix colours for all layers.
 18/09/2019  : Versioncheck & set max mech layers for AD19 & later

Can already iterate 1 to 64 mech layers in AD17! (see MechLayerNames-test.pas)
 tbd: will it crash?

..................................................................................}
const
    NoColour          = 'ncol';
    ADVersion19       = 19;
    AD17MaxMechLayers = 32;     // scripting API has broken consts from TV6_Layer
    AD19MaxMechLayers = 1024; 

var
    Board         : IPCB_Board;
    LayerStack    : IPCB_LayerStack_V7;
    LayerObj_V7   : IPCB_LayerObject_V7;
    MechLayer     : IPCB_MechanicalLayer;
    MechPairs     : IPCB_MechanicalLayerPairs;
    VerMajor      : WideString;
    MaxMechLayers : integer;
    FileName      : String;
    INIFile       : TIniFile;
    Flag          : Integer;
    ML1, ML2      : integer;
    i, j          : Integer;

{.................................................................................}
function Version(const dummy : boolean) : TStringList;
begin
    Result := TStringList.Create;
    Result.Delimiter := '.';
    Result.Duplicates := dupAccept;
    Result.DelimitedText := Client.GetProductVersion;
end;

Procedure ExportMechLayerInfo;
var
    SaveDialog  : TSaveDialog;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then exit;

    VerMajor := Version(true).Strings(0);

    MaxMechLayers := AD17MaxMechLayers;
    if (VerMajor >= ADVersion19) then 
        MaxMechLayers := AD19MaxMechLayers;

    SaveDialog        := TSaveDialog.Create(Application);
    SaveDialog.Title  := 'Save Mech Layer Names to *.ini file';
    SaveDialog.Filter := 'INI file (*.ini)|*.ini';
    FileName := ExtractFilePath(Board.FileName);
    SaveDialog.FileName := ChangeFileExt(FileName, '');

    Flag := SaveDialog.Execute;
    if (not Flag) then exit;

    // Get file & set extension
    FileName := SaveDialog.FileName;
    FileName := ChangeFileExt(FileName, '.ini');
    IniFile := TIniFile.Create(FileName);

    LayerStack := Board.LayerStack_V7;
    MechPairs  := Board.MechanicalPairs;

    for i := 1 to MaxMechLayers do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        MechLayer := LayerStack.LayerObject_V7[ML1];

        IniFile.WriteString('MechLayer' + IntToStr(i), 'Name', Board.LayerName(ML1) );    //MechLayer.Name);

        for j := 1 to MaxMechLayers do
        begin
            ML2 := LayerUtils.MechanicalLayer(j);
            if MechPairs.PairDefined(ML1, ML2) then
                IniFile.WriteString('MechLayer' + IntToStr(i), 'Pair', Board.LayerName(ML2) );
        end;
        IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'Enabled', MechLayer.MechanicalLayerEnabled);
        IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'Show',    MechLayer.IsDisplayed[Board]);
        IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'Sheet',   MechLayer.LinkToSheet);
        IniFile.WriteBool  ('MechLayer' + IntToStr(i), 'SLM',     MechLayer.DisplayInSingleLayerMode);
        IniFile.WriteString('MechLayer' + IntToStr(i), 'Color',   ColorToString(Board.LayerColor[ML1]) );
    end;
end;


Procedure ImportMechLayerInfo;
var
    PCBSysOpts : IPCB_SystemOptions;
    OpenDialog : TOpenDialog;
    MechLayer2 : IPCB_MechanicalLayer;
    MPairLayer : String;
    LColour    : TColor;

begin
    Board := PCBServer.GetCurrentPCBBoard;
    if Board = nil then exit;
    PCBSysOpts := PCBServer.SystemOptions;
    If PCBSysOpts = Nil Then exit;

    VerMajor := Version(true).Strings(0);

    MaxMechLayers := AD17MaxMechLayers;
    if (VerMajor >= ADVersion19) then 
        MaxMechLayers := AD19MaxMechLayers;

    OpenDialog        := TOpenDialog.Create(Application);
    OpenDialog.Title  := 'Import Mech Layer Names from *.ini file';
    OpenDialog.Filter := 'INI file (*.ini)|*.ini';
//    OpenDialog.InitialDir := ExtractFilePath(Board.FileName);
    OpenDialog.FileName := '';
    Flag := OpenDialog.Execute;
    if (not Flag) then exit;

    FileName := OpenDialog.FileName;
    IniFile := TIniFile.Create(FileName);

    LayerStack := Board.LayerStack_V7;
    MechPairs  := Board.MechanicalPairs;

    For i := 1 To MaxMechLayers do
    begin
        ML1 := LayerUtils.MechanicalLayer(i);
        MechLayer := LayerStack.LayerObject_V7[ML1];

        MechLayer.Name := IniFile.ReadString('MechLayer' + IntToStr(i), 'Name',  '');
        MPairLayer     := IniFile.ReadString('MechLayer' + IntToStr(i), 'Pair',  '');

    // remove existing mechpairs & add new ones.
    // potentially new layer names in this file are of mech pair; only check parsed ones.
        for j := 1 to (i -1) do
        begin
            ML2 := LayerUtils.MechanicalLayer(j);
            // remove pair including backwards ones !
            if MechPairs.PairDefined(ML2, ML1) then
                MechPairs.RemovePair(ML2, ML1);
            if MechPairs.PairDefined(ML1, ML2) then
                MechPairs.RemovePair(ML1, ML2);

            MechLayer2 := LayerStack.LayerObject_V7[ML2];
            if (MPairLayer = MechLayer2.Name) and not MechPairs.PairDefined(ML2, ML1) then
                MechPairs.AddPair(ML2, ML1);
        end;

        If Not MechLayer.MechanicalLayerEnabled then
            MechLayer.MechanicalLayerEnabled := IniFile.ReadBool('MechLayer' + IntToStr(i), 'Enabled', True);

        MechLayer.LinkToSheet              := IniFile.ReadBool('MechLayer' + IntToStr(i), 'Sheet', False);
        MechLayer.DisplayInSingleLayerMode := IniFile.ReadBool('MechLayer' + IntToStr(i), 'SLM',   False);
        MechLayer.IsDisplayed[Board]       := IniFile.ReadBool('MechLayer' + IntToStr(i), 'Show',  True);
        LColour                            := IniFile.ReadString('MechLayer' + IntToStr(i), 'Color', NoColour);
        if LColour <> NoColour then
            PCBSysOpts.LayerColors[ML1] := StringToColor( LColour);

    end;

    Board.ViewManager_UpdateLayerTabs;
    ShowInfo('The names & colours assigned to layers (& mech pairs) have been updated.');
end;

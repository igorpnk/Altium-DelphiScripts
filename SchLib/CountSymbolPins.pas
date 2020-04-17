{.............................................................................
  CountSymbolPins.pas
  SchLib
  Count pins of all parts of Symbols
  Report part cnt & pin xy & len

  Disabled --> Save as parameter to allow use by FSO/Inspector

 from Altium Summary Demo how to iterate through a schematic library.

 Version 1.0
 BL Miller
17/04/2020 v1.10  added pin x, y & len

..............................................................................}

const
    bDisplay      = true;
    bAddParameter = false;

Procedure GenerateReport(Report : TStringList, Filename : WideString);
Var
    WS       : IWorkspace;
    Prj      : IProject;
    Document : IServerDocument;
    Filepath : WideString;

Begin
    WS  := GetWorkspace;
    If WS <> Nil Then
    begin
       Prj := WS.DM_FocusedProject;
       If Prj <> Nil Then
          Filepath := ExtractFilePath(Prj.DM_ProjectFullPath);
    end;
    
    If length(Filepath) < 5 then Filepath := 'c:\temp\';
 
    Filepath := Filepath + Filename; 

    Report.SaveToFile(Filepath);

    Document := Client.OpenDocument('Text',Filepath);
    if bDisplay and (Document <> Nil) Then
    begin
        Client.ShowDocument(Document);
        if (Document.GetIsShown <> 0 ) then
            Document.DoFileLoad;
    end;
End;

{..............................................................................}
Procedure LoadPinCountParameter;
Const
    SymbolPinCount = 'SymbolPinCount';   //parameter name.

Var
    CurrentLib      : ISch_Lib;
    LibraryIterator : ISch_Iterator;
    Iterator        : ISch_Iterator;
    Units           : TUnits;
    UnitsSys        : TUnitSystem;
    AnIndex         : Integer;
    i               : integer;
    LibComp         : ISch_Component;
    Item            : ISch_Line;
    OldItem         : ISch_Line;
    Pin             : ISch_Pin;
    S               : TDynamicString;
    ReportInfo      : TStringList;
    CompName        : TString;
    PinCount        : Integer;

    PartCount       : Integer;    // sub parts (multi-gate) of 1 component
    PrevPID         : Integer;
    ThisPID         : Integer;

    LocX, LocY      : TCoord;
    PDes            : TCoord;
    PLength         :  TCoord;

Begin
    If SchServer = Nil Then Exit;
    CurrentLib := SchServer.GetCurrentSchDocument;
    If CurrentLib = Nil Then Exit;

    If CurrentLib.ObjectID <> eSchLib Then
    Begin
         ShowError('Please open a schematic library.');
         Exit;
    End;


    Units    := GetCurrentDocumentUnit;
    UnitsSys := GetCurrentDocumentUnitSystem;
    ReportInfo := TStringList.Create;

    LibraryIterator := CurrentLib.SchLibIterator_Create;
    LibraryIterator.AddFilter_ObjectSet(MkSet(eSchComponent));

    Try
        // find the aliases for the current library component.
        LibComp := LibraryIterator.FirstSchObject;
        While LibComp <> Nil Do
        Begin
            CompName : = LibComp.LibReference;
            ReportInfo.Add('Comp Name: ' + CompName + ' ' + LibComp.Designator.Text);
            PartCount := LibComp.PartCount;
            ReportInfo.Add('Number parts : ' + IntToStr(PartCount));

            Iterator := LibComp.SchIterator_Create;
            Iterator.AddFilter_ObjectSet(MkSet(ePin));
            ReportInfo.Add('PartID : ' + IntToStr(LibComp.CurrentPartID));
            PinCount := 0;
            ThisPID   := LibComp.CurrentPartID;

            Try
                Item := Iterator.FirstSchObject;
                While Item <> Nil Do
                Begin
                    PrevPID := ThisPID;
                    ThisPID := Item.OwnerPartId;
                    // check if into a new part of the component.
                    If ThisPID <> PrevPID Then
                    Begin
                        ReportInfo.Add('PartID : ' + IntToStr(PrevPID) + ' Pin Count : ' + IntToStr(PinCount));
                   //     PinCount := 0;
                    End;

                    If Item.ObjectID = ePin Then
                    Begin
                        Pin := Item;
                        PDes    := Pin.Designator;
                        PLength := Pin.PinLength;
                        LocX    := Pin.Location.X;
                        LocY    := Pin.Location.Y;
// CoordUnitToStringNoUnit(L1.x, Units)

                        ReportInfo.Add('Pin ' + PDes + ' X : ' + CoordUnitToStringWithAccuracy(LocX, Units, 5, 10)  + '   Y : ' + CoordUnitToStringwithAccuracy(LocY, Units, 5, 10)  + '   len : '+ CoordUnitToStringWithAccuracy(PLength, Units, 5, 10));
                        Inc(PinCount);
                    End;

                    Item := Iterator.NextSchObject;
                End;
            Finally
                LibComp.SchIterator_Destroy(Iterator);
            End;
            
            // from SchParameters.pas
//            if bAddParameter then SchParameterSet( LibComp, SymbolPinCount, IntToStr(PinCount) );

            ReportInfo.Add('');
            LibComp := LibraryIterator.NextSchObject;
        End;

    Finally
        CurrentLib.GraphicallyInvalidate;
        CurrentLib.OwnerDocument.UpdateDisplayForCurrentSheet;
        // we are finished fetching symbols of the current library.
        CurrentLib.SchIterator_Destroy(LibraryIterator);
    End;


    ReportInfo.Insert(0,'SchLib Part Pin Count Report');
    ReportInfo.Insert(1,'------------------------------');
    ReportInfo.Insert(2, CurrentLib.DocumentName);
    GenerateReport(ReportInfo, 'SchLibPartPinCountReport.txt');

    ReportInfo.Free;
End;

{..............................................................................}
End.


{ CompPlaceFromLib.pas
  Place a component from IntLib or DbLib.
  Requires hardcoded comp libref & Library Name
  DBLib requires Tablename
  Only supports SchDoc.

  Works with SchLib if is part of LibPkg & focused project.

  Author: BLM
  20190511 : 1.0  first cut
  20200410 : 1.1  Added messages. Tried to fix location for DbLib placing.
  20201007   1.2  Fix the comp from DB so it places the requested part.
  20201231   1.21 Tidy code; sanitize.
}

Procedure PlaceCompFL();
Var
    WS           : IWorkspace;
    Prj          : IProject;
    IntLibMan    : IIntegratedLibraryManager;
    Doc          : IDocument;
    CurrentSch   : ISch_Document;

    Units        : TUnits;
    UnitsSys     : TUnitSystem;

    CompLoc        : WideString;
    FoundLocation  : WideString;
    FoundLibName   : WideString;

    LibType        : ILibraryType;
    LibIdKind      : ILibIdentifierKind;
    LibName        : WideString;
    DBTableName    : WideString;

    SelSymbol      : WideString;

    PList          : TParameterList;
    Parameters     : TDynamicString;
    SchComp        : ISch_Component;

    Location       : TLocation;

    sComment        : WideString;
    sDes            : WideString;

Begin
// Comp library reference name
    SelSymbol :=  '1K_0402_5%_1/16W';                  // Comp.LibReference;

// Source library name (& table)
    LibType := eLibSource;
    LibType := eLibIntegrated;      // IntLib == eLibIntegrated
    LibType := eLibDatabase;        // DbLib == eLibDatabase

    DBTableName := '';

    case LibType of
    eLibSource :
      begin
        LibName     := 'Symbols.SchLib';                   // Comp.SourceLibraryName
        SelSymbol   := 'RES_BlueRect_2Pin';
      end;
    eLibIntegrated :   //IntLib
      begin
        LibName     := 'Resistor.IntLib';                  // Comp.SourceLibraryName
      end;
    eLibDatabase :
      begin
        LibName     := 'Database_Libs1.DbLib';             // Comp.DatabaseLibraryName
        DBTableName := 'Resistors';                        // Comp.DatabaseTableName
      end;
    end;


    WS  := GetWorkspace;
    If not Assigned(WS) Then Exit;
    Prj := WS.DM_FocusedProject;
//    If not Assigned(Prj) Then Exit;

    Doc := WS.DM_FocusedDocument;

    If Doc.DM_DocumentKind <> cDocKind_Sch Then exit;
    If not Assigned(SchServer) Then Exit;

    CurrentSch := SchServer.GetCurrentSchDocument;
    // if you have not double clicked on Doc it may be open in project but not loaded.
    If not Assigned(CurrentSch) Then
        CurrentSch := SchServer.LoadSchDocumentByPath(Doc.DM_FullPath);
    If not Assigned(CurrentSch) Then Exit;

    Units    := GetCurrentDocumentUnit;
    UnitsSys := CurrentSch.UnitSystem;
    UnitsSys := GetCurrentDocumentUnitSystem;

    IntLibMan := IntegratedLibraryManager;
    If not Assigned(IntLibMan) Then Exit;


//  Create parameters string & list for diff methods.
    PList := TParameterList.Create;
    PList.ClearAllParameters;
    PList.SetState_FromString(Parameters);
    PList.SetState_AddParameterAsString ('Orientation', '1');               // 90 degrees
    PList.SetState_AddParameterAsString ('Location.X',  MilsToCoord(1000) );
    PList.SetState_AddParameterAsString ('Location.Y',  MilsToCoord(1000) );
    PList.SetState_AddParameterAsString ('Designator',  'DumR');
    PList.SetState_AddParameterAsString ('Comment'   ,  'dummy comment');
    Parameters := PList.GetState_ToString;
//    Parameters := 'Orientation=1|Location.X=10000000|Location.Y=20000000';

    FoundLocation := '';
    LibIdKind := eLibIdentifierKind_NameWithType;      // eLibIdentifierKind_Any;

 // Initialize the robots in Schematic editor.
    SchServer.ProcessControl.PreProcess(CurrentSch, '');

    if (LibType = eLibIntegrated) or (LibType = eLibSource) then   //IntLib
    begin
//        GetLibIdentifierKindFromString(LibName, cDocKind_Schlib);           // 83

//  needs full path with my IntLibs     SelSymLib not enough
       CompLoc := IntLibMan.FindComponentLibraryPath(LibIdKind, LibName, SelSymbol);
       CompLoc := IntLibMan.GetComponentLocation(LibName, SelSymbol, FoundLocation);

//   alt. method: SCModel := SchServer.LoadComponentFromLibrary(CompLibRef, CompLoc)
       if CompLoc <> '' then
           IntLibMan.PlaceLibraryComponent(SelSymbol, FoundLocation, Parameters)
       else
           Showmessage('Sorry, component not found in Lib ' + LibName);
    end;


    if LibType = eLibDatabase then
    begin

        CompLoc := IntLibMan.GetComponentLocationFromDatabase(LibName, DBTableName,  SelSymbol, FoundLocation);
        if CompLoc <> '' then
        begin

//   warning: "Parameters" are still loaded for any server until cleared!

//     missing API fn PlaceDBLibraryComponent()
            SchComp := SchServer.LoadComponentFromDatabaseLibrary(LibName, DBTableName, SelSymbol );

// retrieve from ParameterList..
            sComment := '';
            PList.GetState_ParameterAsString('Comment', sComment);
            sDes := '';
            PList.GetState_ParameterAsString('Designator', sDes);

//            PList.SetState_AddOrReplaceParameter('Location.X' , Location.X, true);
//            PList.SetState_AddOrReplaceParameter('Location.Y' , Location.Y, true);
            Location := Point(MilsToCoord(1200), MilsToCoord(1200) );

//  below does not work right as part drwn offset from location.
//            SchComp.SetState_Location := Location;
//            SchComp.Location ;

            SchComp.MoveToXY(Location.X, Location.Y);
            SchComp.SetState_Orientation := 0;                     // 0 degrees


            SchComp.Designator.Text := sDes;
            SchComp.Comment.Text := sComment;
            SchComp.SetState_xSizeySize;          // recalc bounding rect after parameter change

            SchServer.GetCurrentSchDocument.RegisterSchObjectInContainer(SchComp);
            SchServer.RobotManager.SendMessage(CurrentSch.I_ObjectAddress,c_BroadCast, SCHM_PrimitiveRegistration,SchComp.I_ObjectAddress);

            SchComp.GraphicallyInvalidate;
        end
        else
            Showmessage('Sorry, component not found in DbLib ');
    end;

//    ResetParameters;

    PList.Free;

    // Clean up the robots in Schematic editor
    SchServer.ProcessControl.PostProcess(CurrentSch, '');

    SchServer.GetCurrentSchDocument.GraphicallyInvalidate;

end;


Make a project to hold both .pas files if wish to use one click project processing.

CompSourceLibReLinker.pas 
These exposed procedure entry points are setup for single focused document action.
- SchDoc/Lib relinking
- PcbDoc FP relinking

PrjLibReLinker.pas
These exposed procedure entry points are setup to iterate over all project documents
in the sequence:-
- SchLib, to link FPmodels to source PcbLib(s)
- SchDoc, to link comps & comp models to source libs
- PcbDoc, to link footprints to source PcbLib(s)

All summary reports are created in subfolder "Reports"


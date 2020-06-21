object FormSelectBadConnections: TFormSelectBadConnections
  Left = 0
  Top = 0
  Caption = 'Select Bad Connections'
  ClientHeight = 179
  ClientWidth = 216
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  FormStyle = fsStayOnTop
  OldCreateOrder = False
  OnCreate = FormSelectBadConnectionsCreate
  FormKind = fkNormal
  PixelsPerInch = 96
  TextHeight = 13
  object Label1: TLabel
    Left = 24
    Top = 8
    Width = 57
    Height = 13
    Caption = 'Tolerance:'
  end
  object Label2: TLabel
    Left = 24
    Top = 56
    Width = 72
    Height = 13
    Caption = 'Active Layers:'
  end
  object EditTolerance: TEdit
    Left = 16
    Top = 24
    Width = 72
    Height = 24
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -13
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    TabOrder = 0
    Text = '0.1'
    OnChange = EditToleranceChange
  end
  object ButtonOK: TButton
    Left = 128
    Top = 144
    Width = 75
    Height = 25
    Caption = 'OK'
    Default = True
    TabOrder = 1
    OnClick = ButtonOKClick
  end
  object ButtonCancel: TButton
    Left = 16
    Top = 144
    Width = 75
    Height = 25
    Caption = 'Cancel'
    TabOrder = 2
    OnClick = ButtonCancelClick
  end
  object RadioGroupUnits: TRadioGroup
    Left = 104
    Top = 8
    Width = 104
    Height = 40
    Caption = 'Units:'
    Columns = 2
    ItemIndex = 0
    Items.Strings = (
      'mil'
      'mm')
    TabOrder = 3
    OnClick = RadioGroupUnitsClick
  end
  object CheckBoxCopper: TCheckBox
    Left = 16
    Top = 72
    Width = 56
    Height = 17
    Caption = 'Copper'
    Checked = True
    State = cbChecked
    TabOrder = 4
    OnClick = CheckBoxCopperClick
  end
  object CheckBoxMech: TCheckBox
    Left = 88
    Top = 72
    Width = 48
    Height = 17
    Caption = 'Mech'
    TabOrder = 5
    OnClick = CheckBoxMechClick
  end
  object CheckBoxCurrent: TCheckBox
    Left = 152
    Top = 72
    Width = 97
    Height = 17
    Caption = 'Current'
    Checked = True
    State = cbChecked
    TabOrder = 6
    OnClick = CheckBoxCurrentClick
  end
  object ClearMMPanel: TButton
    Left = 16
    Top = 104
    Width = 88
    Height = 25
    Caption = 'Clear MMPanel'
    TabOrder = 7
    OnClick = ClearMMPanelClick
  end
end

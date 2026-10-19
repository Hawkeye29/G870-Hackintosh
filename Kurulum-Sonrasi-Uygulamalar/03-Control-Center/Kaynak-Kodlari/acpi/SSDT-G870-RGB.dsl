/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20200925 (64-bit version)
 * Copyright (c) 2000 - 2020 Intel Corporation
 *
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of outputs/g870-control-center/acpi/SSDT-G870-RGB.aml, Sat Oct 17 18:30:04 2026
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x0000047F (1151)
 *     Revision         0x02
 *     Checksum         0xE7
 *     OEM ID           "G870"
 *     OEM Table ID     "RGBSAFE"
 *     OEM Revision     0x00000001 (1)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20200925 (538970405)
 */
DefinitionBlock ("", "SSDT", 2, "G870", "RGBSAFE", 0x00000001)
{
    External (_SB_.GWMI, DeviceObj)
    External (_SB_.PC00.LPCB.EC0_.ECMT, MutexObj)
    External (_SB_.PC00.LPCB.EC0_.ECOK, IntObj)
    External (_SB_.PC00.LPCB.EC0_.LKBA, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBB, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBC, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBE, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBG, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBL, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBM, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBR, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKBS, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.LKCC, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.RGBK, FieldUnitObj)
    External (_SB_.PC00.LPCB.EC0_.WKCL, FieldUnitObj)

    Scope (\_SB.GWMI)
    {
        // Read-only transport identity: no EC access or light changes.
        Method (GRCQ, 0, NotSerialized)
        {
            Return (0x47524202)
        }

        Method (GRGB, 1, Serialized)
        {
            If (Acquire (\_SB.PC00.LPCB.EC0.ECMT, 0x0064))
            {
                Return (0x04)
            }

            If (!\_SB.PC00.LPCB.EC0.ECOK)
            {
                Release (\_SB.PC00.LPCB.EC0.ECMT)
                Return (0x02)
            }

            If (!\_SB.PC00.LPCB.EC0.RGBK)
            {
                Release (\_SB.PC00.LPCB.EC0.ECMT)
                Return (0x02)
            }

            Local0 = ((Arg0 >> 0x1C) & 0x0F)
            Local1 = ((Arg0 >> 0x18) & 0x0F)
            If (!((Local0 == One) || ((Local0 == 0x03) || ((
                Local0 == 0x06) || (Local0 == 0x07)))))
            {
                Release (\_SB.PC00.LPCB.EC0.ECMT)
                Return (0x02)
            }

            If ((Local1 > 0x02))
            {
                Release (\_SB.PC00.LPCB.EC0.ECMT)
                Return (0x02)
            }

            Local4 = (Arg0 >> 0x20)
            If (Local4 == Zero)
            {
                Local4 = 0x06
            }
            ElseIf (!((Local4 == 0x03) || (Local4 == 0x04) || (Local4 == 0x05)))
            {
                Release (\_SB.PC00.LPCB.EC0.ECMT)
                Return (0x02)
            }
            \_SB.PC00.LPCB.EC0.LKBC = Zero
            \_SB.PC00.LPCB.EC0.LKBA = Local4
            \_SB.PC00.LPCB.EC0.LKBB = (Arg0 & 0xFF)
            \_SB.PC00.LPCB.EC0.LKBG = ((Arg0 >> 0x08) & 0xFF)
            \_SB.PC00.LPCB.EC0.LKBR = ((Arg0 >> 0x10) & 0xFF)
            If ((Local1 == Zero))
            {
                Local2 = 0x02
            }
            Else
            {
                Local2 = (Local1 - One)
            }

            \_SB.PC00.LPCB.EC0.LKBL = Local2
            \_SB.PC00.LPCB.EC0.WKCL = Local2
            \_SB.PC00.LPCB.EC0.LKBM = Local0
            \_SB.PC00.LPCB.EC0.LKCC = One
            Local3 = Zero
            While ((\_SB.PC00.LPCB.EC0.LKBE != One))
            {
                If ((Local3 >= 0xFA))
                {
                    Release (\_SB.PC00.LPCB.EC0.ECMT)
                    Return (0x03)
                }

                Sleep (One)
                Local3++
            }

            \_SB.PC00.LPCB.EC0.LKBE = Zero
            \_SB.PC00.LPCB.EC0.LKBS = One
            Local3 = Zero
            While ((\_SB.PC00.LPCB.EC0.LKBE != One))
            {
                If ((Local3 >= 0xFA))
                {
                    Release (\_SB.PC00.LPCB.EC0.ECMT)
                    Return (0x03)
                }

                Sleep (One)
                Local3++
            }

            Release (\_SB.PC00.LPCB.EC0.ECMT)
            Return (One)
        }
    }
}

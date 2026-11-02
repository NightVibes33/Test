#!/usr/bin/env python3
"""Instruction-grounded extraction of the ORIGINAL iOS 27.2 Pumpkin getter.

The iPhoneOS 24B5110a getter delegates to _MGCopyAnswer. The backing source
is unresolved until the resolver, its downstream calls, and the distinct
HomeView build have been examined. This program never fabricates an answer.
"""
import argparse
import json
from pathlib import Path
import re

ANSI = re.compile(r"\x1b\[[0-9;]*m")
INSTRUCTION = re.compile(
    r"^\s*(0x[0-9a-fA-F]{8,16}):\s+(?:(?:[0-9a-fA-F]{2}\s+){4})?"
    r"([a-z][a-z0-9._]*)\b\s*(.*)$", re.I)
LABEL = re.compile(r"^((?:_[A-Za-z][\w$.]*|sub_[0-9a-fA-F]+)):\s*$")
SOURCE_SYMBOLS = {
    "IORegistry": ("IORegistryEntry", "IOServiceGetMatching", "IORegistryGet"),
    "NVRAM": ("IODTNVRAM", "IONVRAM", "PEGetNVRAM", "nvram_get"),
    "sysctl": ("sysctl",),
    "MobileGestalt_cache": ("MGCopyAnswer", "MobileGestaltCache", "MGCache"),
    "DeviceTree": ("IODeviceTree", "dt_get_prop"),
    "PlatformExpert": ("PEGet", "PlatformExpert"),
    "entitlement": ("SecTaskCopyValueForEntitlement", "audit_token_to_entitlement"),
}
TARGET = "_MobileGestalt_get_pumpkinMode"


def parse_functions(output):
    """Return recognized assembler sections, never cross into later symbols."""
    text = ANSI.sub("", output)
    functions = {}
    current = None
    for line in text.splitlines():
        label = LABEL.match(line.strip())
        if label:
            current = label.group(1)
            functions.setdefault(current, [])
            continue
        match = INSTRUCTION.match(line)
        if match and current is not None:
            functions[current].append({
                "address": match.group(1).lower(),
                "opcode": match.group(2).lower(),
                "operand": match.group(3).strip(),
                "text": line.strip()[:350],
            })
    return functions


def analyze(text):
    clean = ANSI.sub("", text)
    functions = parse_functions(clean)
    instructions = functions.get(TARGET, [])
    calls = [i for i in instructions
             if i["opcode"] in ("bl", "blr", "blraaz", "blrabz", "blraa", "blrab")]
    direct = [i for i in calls if i["opcode"] == "bl"]
    indirect = [i for i in calls if i["opcode"] != "bl"]
    source_hints = []
    for call in direct:
        for source, symbols in SOURCE_SYMBOLS.items():
            if any(symbol.lower() in call["operand"].lower() for symbol in symbols):
                source_hints.append({
                    "source": source, "instruction": call["text"],
                    "evidence": "named direct call; backing dataflow not traced",
                })
    op = lambda code, token: any(
        i["opcode"] == code and token in i["operand"] for i in instructions)
    direct_mg = any("_MGCopyAnswer" in i["operand"] for i in direct)
    cfnumber_type = any("CFNumberGetTypeID" in i["operand"] for i in direct)
    cfnumber_value = any("CFNumberGetValue" in i["operand"] for i in direct)
    type_check = cfnumber_type and op("cmp", "x21")
    sentinel = (op("mov", "w21, #0xffffffff")
                and op("str", "w21, [sp, #0xc]")
                and op("ldr", "w21, [sp, #0xc]"))
    # The pointer is an address of an NSCFConstantString object, not the
    # plaintext value. Reading the key requires dereferencing CFString data.
    pointer = None
    for index, instruction in enumerate(instructions[:-1]):
        m = re.match(r"x0,\s*(0x[0-9a-fA-F]+)", instruction["operand"])
        following = instructions[index + 1]
        n = re.match(r"x0,\s*x0,\s*#(0x[0-9a-fA-F]+)", following["operand"])
        if instruction["opcode"] == "adrp" and following["opcode"] == "add" and m and n:
            pointer = hex(int(m.group(1), 16) + int(n.group(1), 16))
            break
    bad = re.search(r"(?im)^\s*(?:error:|unknown flag:|usage: ipsw dyld disass)", clean)
    valid = bool(instructions) and len(instructions) >= 8 and not bad
    result = {
        "target": TARGET,
        "source_build": "iPhoneOS 27.2 beta 4 (24B5110a)",
        "function_entry": instructions[0]["address"] if instructions else None,
        "function_only_instructions": True,
        "instruction_level_disassembly_present": valid,
        "instruction_count": len(instructions),
        "direct_call_count": len(direct),
        "indirect_call_count": len(indirect),
        "return_instruction_count": sum(
            i["opcode"] in ("ret", "retaa", "retab") for i in instructions),
        "direct_calls": direct[:100],
        "indirect_calls": indirect[:40],
        "symbol_named_source_hints": source_hints[:40],
        "MGCopyAnswer_directly_called": direct_mg,
        "CFNumber_type_id_checked": bool(type_check),
        "CFNumber_value_requested": cfnumber_value,
        "minus_one_failure_sentinel_initialized_and_reloaded": bool(sentinel),
        "MGCopyAnswer_key_constant_object_pointer": pointer,
        "MGCopyAnswer_key_plaintext_verified": False,
        "getter_implementation_class": (
            "MGCopyAnswer_wrapped_numeric_answer" if
            valid and direct_mg and cfnumber_type and cfnumber_value and sentinel
            else "not_established"),
        "getter_direct_IORegistry_or_NVRAM_call": any(
            item["source"] in ("IORegistry", "NVRAM") for item in source_hints),
        "backing_source_verified": False,
        "actual_pumpkinmode_return_verified": False,
        "experimental_chosen_property_used_by_apple": None,
        "homeview_24V514_getter_checked": False,
        "note": ("This proves the wrapper's direct MGCopyAnswer call in iPhoneOS. "
                 "A constant-object pointer is not the decoded key value. "
                 "MGCopyAnswer internals and HomeView build remain unverified.")
    }
    return result


def analyze_resolver(text):
    functions = parse_functions(text)
    inst = functions.get("_MGCopyAnswer", [])
    direct = [i for i in inst if i["opcode"] == "bl"]
    indirect = [i for i in inst if i["opcode"] in (
        "blr", "blraaz", "blrabz", "blraa", "blrab")]
    hints = []
    for i in direct:
        for source, symbols in SOURCE_SYMBOLS.items():
            if any(s.lower() in i["operand"].lower() for s in symbols):
                hints.append({"source": source, "call": i["text"]})
    tail = next((i["operand"].split(";", 1)[0].strip()
                 for i in reversed(inst) if i["opcode"] == "b"), None)
    return {
        "target": "_MGCopyAnswer",
        "instruction_stream_present": len(inst) >= 4,
        "entry": inst[0]["address"] if inst else None,
        "instruction_count": len(inst),
        "direct_calls": direct[:120],
        "indirect_calls": indirect[:40],
        "named_callsite_hints": hints[:60],
        "MGGetGlobalCache_called_directly": any(
            "_MGGetGlobalCache" in i["operand"] for i in direct),
        "tail_branch_target": tail,
        "tail_branch_requires_followup": bool(tail),
        "potentially_truncated": bool(inst and inst[-1]["opcode"] not in (
            "ret", "retab", "retaa")),
        "actual_resolver_backing_source_verified": False,
        "note": "Resolver instruction listing only; deeper callees and dataflow must be traced."
    }


def analyze_followup(text, expected_entry):
    """Return evidence only for a function beginning at the exact vaddr."""
    candidates = parse_functions(text)
    function = next((rows for rows in candidates.values()
                     if rows and rows[0]["address"] == expected_entry.lower()), [])
    direct = [i for i in function if i["opcode"] == "bl"]
    indirect = [i for i in function if i["opcode"] in (
        "blr", "blraa", "blrab", "blraaz", "blrabz")]
    return {
        "expected_entry": expected_entry,
        "entry_verified_from_original_disassembly": bool(function),
        "instruction_count": len(function),
        "direct_calls": direct[:100],
        "indirect_calls": indirect[:40],
        "dataflow_to_PumpkinMode_verified": False,
        "classification": "unresolved_cache_dispatch_or_helper",
    }


def analyze_global_cache(text):
    inst = parse_functions(text).get("_MGGetGlobalCache", [])
    return {
        "target": "_MGGetGlobalCache",
        "instruction_stream_present": len(inst) >= 4,
        "entry": inst[0]["address"] if inst else None,
        "instructions_in_symbol": len(inst),
        "direct_calls": [i for i in inst if i["opcode"] == "bl"][:100],
        "backing_source_verified": False,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("disassembly")
    ap.add_argument("--resolver")
    ap.add_argument("--global-cache")
    ap.add_argument("--resolver-tail")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    result = analyze(Path(args.disassembly).read_text(errors="replace"))
    if args.resolver:
        result["MGCopyAnswer_resolver"] = analyze_resolver(
            Path(args.resolver).read_text(errors="replace"))
    if args.global_cache:
        result["MGGetGlobalCache"] = analyze_global_cache(
            Path(args.global_cache).read_text(errors="replace"))
    if args.resolver_tail:
        result["MGCopyAnswer_tail"] = analyze_followup(
            Path(args.resolver_tail).read_text(errors="replace"), "0x1afe68848")
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        k: result[k] for k in ("function_entry", "instruction_count",
           "MGCopyAnswer_directly_called", "getter_implementation_class",
           "MGCopyAnswer_key_constant_object_pointer")}, indent=2))
    if not result["instruction_level_disassembly_present"]:
        raise SystemExit("Missing authentic Pumpkin getter instructions")
    if result["getter_implementation_class"] != "MGCopyAnswer_wrapped_numeric_answer":
        raise SystemExit("Expected iPhoneOS 24B5110a getter control flow not established")


if __name__ == "__main__":
    main()

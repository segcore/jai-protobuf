/**
 * Parse protobuf files
 */

ProtoFile :: struct {
    edition: string; // Edition or syntax version. Syntax "proto3" is edition "proto3".
    definitions: [..]ProtoDefinition;
}

ProtoDefinition :: struct {
    kind : ProtoDefinitionKind;
    fields : [..]ProtoField;
}

ProtoDefinitionKind :: enum {
    MESSAGE;
    ENUM;
}

ProtoField :: struct {
    type : ProtoType;
    type_name : string;
    field_number: int;
    name: string;
}

ProtoValue :: union {
    sint : s64;
    uint : u64;
    floating : float64;
    str: string;
    bytes: []u8;
}

parse_proto :: (data: string) -> ProtoFile {
    out: ProtoFile;
    p: Parser;
    p.text = data;

    while parse_primary(*p, *out) {
    }

    return out;
}

parse_primary :: (p: *Parser, out: *ProtoFile) -> keep_going: bool {
    ok, id := parse(p, TokenKind.ID);
    if !ok {
        t := next(p);
        return t.kind != .EOF;
    }

    if id == {
        case "syntax";
            ok = parse(p, TokenKind.EQ);
            if !ok return true;
            ok=, str := parse(p, TokenKind.STRING);
            if !ok return true;
            ok = parse(p, TokenKind.SEMICOLON);
            if !ok return true;
            out.edition = str;
        case "message";
            ok=, message_name := parse(p, .ID);
            if !ok return true;

            defn: *ProtoDefinition = array_add(*out.definitions);
            defn.kind = .MESSAGE;

            ok = parse(p, .OCURLY);
            if !ok return true;
            t: Token;
            while t.kind != .EOF {
                t = peek(p);
                if t.kind == .CCURLY {
                    next(p);
                    break;
                }
                if t.kind == .ID {
                    parse_field(p, defn);
                } else {
                    log("Unknown item in message");
                }
            }
            return true;
        case;
            log("Unknown ID %", id);
    }

    return true;
}

parse_field :: (p: *Parser, defn: *ProtoDefinition) -> ok: bool {
    field: *ProtoField = array_add(*defn.fields);

    if defn.kind == .MESSAGE {
        ok, type_name := parse(p, .ID);
        if !ok return false;

        field.type_name = type_name;
        if type_name == {
            case "int32";
                field.type = .INT32;
            case;
                log("TODO: type %", type_name);
        }
    }

    ok, name := parse(p, .ID);
    if !ok return false;
    field.name = name;

    ok = parse(p, .EQ);
    if !ok return false;

    ok=, number_str := parse(p, .NUMBER);
    if !ok return false;
    field.field_number = string_to_int(number_str);

    ok = parse(p, .SEMICOLON);
    if !ok return false;

    return true;
}


parse :: (p: *Parser, kind: TokenKind) -> ok: bool, text: string {
    t := peek(p);
    if t.kind != kind {
        log(" > Expected % but got %", kind, t);
        return false, "";
    }
    next(p);
    if t.value return true, t.value;
    return true, t.text;
}

#scope_file

Parser :: struct {
    text: string;
}

TokenKind :: enum {
    UNKNOWN;
    EOF; // end-of-file (end of string)

    SEMICOLON;
    OCURLY;
    CCURLY;
    EQ;

    ID; // Identifier (name)
    NUMBER;
    STRING;
}

Token :: struct {
    kind: TokenKind;
    text: string;
    value: string;
}

next :: (p: *Parser) -> Token {
    t := peek(p);
    advance(*p.text, t.text.count);
    print("next(p) = %\n", t);
    return t;
}

peek :: (p: *Parser) -> Token {
    p.text = trim_left(p.text);
    str := p.text;
    if !str return .{kind = .EOF};
    t: Token;
    i := 0;

    if is_any(str[i], ";{}=") {
        t.text = slice(str, 0, 1);
        if str[i] == {
            case ";";
                t.kind = .SEMICOLON;
                return t;
            case "{";
                t.kind = .OCURLY;
                return t;
            case "}";
                t.kind = .CCURLY;
                return t;
            case "=";
                t.kind = .EQ;
                return t;
            case;
                assert(false, "Unreachable");
        }
    }

    while str[i] >= "0" && str[i] <= "9" {
        i += 1;
    }
    if i return Token.{kind = .NUMBER, text = slice(str, 0, i)};

    while is_alnum(str[i]) {
        i += 1;
    }
    if i return Token.{kind = .ID, text = slice(str, 0, i)};

    if str[0] == "\"" {
        i += 1;
        while i < str.count {
            if str[i] == "\\" {
                i += 2;
            } else if str[i] == "\"" {
                i += 1;
                t.kind = .STRING;
                t.text = slice(str, 0, i);
                t.value = slice(str, 1, i - 2);
                return t;
            } else {
                i += 1;
            }
        }
        // If reaching here, no end-of-" is found, so fail
        t.kind = .UNKNOWN;
        t.text = slice(str, 0, i);
    }

    // Unknown, TODO: eat all we can
    t.kind = .UNKNOWN;
    t.text = slice(str, 0, 1);

    return t;
}

#import "String";

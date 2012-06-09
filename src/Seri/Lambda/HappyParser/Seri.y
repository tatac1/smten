
{

-- vim: ft=haskell
module Seri.Lambda.HappyParser.Seri (parseDecs) where

import Data.Char
import Data.Maybe

import Control.Monad.State

import Seri.Lambda hiding (parseDecs)
import Seri.Utils.Ppr (Ppr(..), render)

}

%name seri_decls
%tokentype { Token }
%error { parseError }
%monad { ParserMonad }
%lexer { lexer } { TokenEOF }

%token 
       '['      { TokenOpenBracket }
       ']'      { TokenCloseBracket }
       '('      { TokenOpenParen }
       ')'      { TokenCloseParen }
       '{'      { TokenOpenBrace }
       '}'      { TokenCloseBrace }
       '->'     { TokenDashArrow }
       '=>'     { TokenEqualsArrow }
       ','      { TokenComma }
       ';'      { TokenSemicolon }
       '.'      { TokenPeriod }
       '|'      { TokenBar }
       '='      { TokenEquals }
       '_'      { TokenUnderscore }
       '@'      { TokenAtSign }
       '%'      { TokenPercent }
       '#'      { TokenHash }
       '\\'      { TokenBackSlash }
       '::'      { TokenDoubleColon }
       conid    { TokenConId $$ }
       varid    { TokenVarId $$ }
       integer  { TokenInteger $$ }
       'data'   { TokenData }
       'forall' { TokenForall }
       'class'  { TokenClass }
       'where'  { TokenWhere }
       'case'   { TokenCase }
       'of'     { TokenOf }
       EOF      { TokenEOF }

%%

body :: { [Dec] }
 : topdecls 
    { $1 }

topdecls :: { [Dec] }
 : topdecl
    { [$1] }
 | topdecls ';' topdecl
    { $1 ++ [$3] }

topdecl :: { Dec }
 : 'data' tycon tyvars '=' constrs
    { DataD $2 $3 $5 }
 | 'class' tycls tyvar 'where' '{' cdecls '}'
    { ClassD $2 [$3] $6}

cdecls :: { [Sig] }
 : cdecl
    { [$1] }
 | cdecls ';' cdecl
    { $1 ++ [$3] }

cdecl :: { Sig }
 : gendecl
    { $1 }

gendecl :: { Sig }
 : var '::' type
    { Sig $1 $3 }

type :: { Type }
 : btype
    { $1 } 
 | btype '->' type
    { AppT (AppT (ConT "->") $1) $3 }
 | forallty
    { $1 }

btype :: { Type }
 : atype
    { $1 }
 | btype atype
    { AppT $1 $2 }

atype :: { Type }
 : gtycon
    { ConT $1 }
 | tyvar
    { VarT $1 }
 | '[' type ']'
    { AppT (ConT "[]") $2 }
 | '(' types_commasep ')'
    { foldl AppT (ConT $ "(" ++ replicate (length $2 - 1) ',' ++ ")") $2 }
 | '(' type ')'
    { $2 }

gtycon :: { String }
 : tycon
    { $1 }
 | '(' ')'
    { "()" }
 | '[' ']'
    { "[]" }
 | '(' commas ')'
    { "(" ++ $2 ++ ")" }
 | '(' '->' ')'
    { "->" }

context :: { [Pred] }
 : class
    { [$1] }
 | '(' classes_commasep ')'
    { $2 }


class :: { Pred }
 : qtycls tyvar
    { Pred $1 [VarT $2] }

constrs :: { [Con] }
 : constr
    { [$1] }
 | constrs constr
    { $1 ++ [$2] }

constr :: { Con }
 : con atypes
    { Con $1 $2 }

exp :: { Exp }
 : exp10
    { $1 }

exp10 :: { Exp }
 : '\\' var_typed '->' exp
    { LamE $2 $4 }
 | 'case' exp 'of' '{' alts '}'
    { CaseE $2 $5 }
 | fexp
    { $1 }

fexp :: { Exp }
 : aexp
    { $1 }
 | fexp aexp
    { AppE $1 $2 }

aexp :: { Exp }
 : qvar_withinfo
    { $1 }
 | gcon_typed
    { ConE $1 }
 | integer
    { IntegerE $1 }
 | '(' exp ')'
    { $2 }

alts :: { [Match] }
 : alt
    { [$1] }
 | alts ';' alt
    { $1 ++ [$3] }

alt :: { Match }
 : pat '->' exp
    { Match $1 $3 }

pat :: { Pat }
 : gcon_typed apats
    { ConP $1 $2 }
 | apat
    { $1 }

apats :: { [Pat] }
 : apat
    { [$1] }
 | apats apat
    { $1 ++ [$2] }

apat :: { Pat }
 : var_typed
    { VarP $1 }
 | gcon_typed
    { ConP $1 [] }
 | '(' '_' '::' type ')'
    { WildP $4 }
 | '(' pat ')'
    { $2 }
 | integer
    { IntegerP $1 }

var_typed :: { Sig }
 : '(' var  '::' type ')'
    { Sig $2 $4 }

gcon_typed :: { Sig }
 : '(' gcon '::' type ')'
    { Sig $2 $4 }

qvar_withinfo :: { Exp }
 : '(' '.' qvar '::' type ')'
    { VarE (Sig $3 $5) Bound }
 | '(' '@' qvar '::' type ')'
    { PrimE (Sig $3 $5) }
 | '(' '%' qvar '::' type ')'
    { VarE (Sig $3 $5) Declared }
 | '(' '#' '{' qtycls atypes '}' qvar '::' type ')' 
    { VarE (Sig $7 $9) (Instance $4 $5) }

gcon :: { String }
 : '(' ')'
    { "()" }
 | '[' ']'
    { "[]" }
 | '(' commas ')'
    { "(" ++ $2 ++ ")" }
 | qcon
    { $1 }

var :: { String }
 : varid
    { $1 }

qvar :: { String }
 : qvarid
    { $1 }

con :: { String }
 : conid
    { $1 }

qcon :: { String }
 : qconid
    { $1 }

tycon :: { String }
 : conid
    { $1 }

tyvar :: { String }
 : varid
    { $1 }

tycls :: { String }
 : conid
    { $1 }

qtycls :: { String }
  : tycls
    { $1 }

qconid :: { String }
  : conid
    { $1 }

qvarid :: { String }
  : varid  { $1 }

commas :: { String }
 : ','
    { "," }
 | commas ','
    { ',':$1 }

types_commasep :: { [Type] }
 : type
    { [$1] }
 | types_commasep ',' type
    { $1 ++ [$3] }

classes_commasep :: { [Pred] }
 : class
    { [$1] }
 | classes_commasep ',' class
    { $1 ++ [$3] }

forallty :: { Type }
 : 'forall' tyvars '.' type
    { ForallT $2 [] $4 }
 | 'forall' tyvars '.' context '=>' type
    { ForallT $2 $4 $6 }

tyvars :: { [String] }
 : tyvar
    { [$1] }
 | tyvars tyvar
    { $1 ++ [$2] }

atypes :: { [Type] }
 : atype
    { [$1] }
 | atypes atype
    { $1 ++ [$2] }



{

data ParserState = ParserState {
    ps_text :: String,
    ps_line :: Integer,
    ps_column :: Integer,
    ps_error :: Maybe String
}

type ParserMonad = State ParserState

parseError :: Token -> ParserMonad a
parseError tok = do
    ln <- gets ps_line
    cl <- gets ps_column
    failE $ "error:" ++ show ln ++ ":" ++ show cl ++ ": parser error at " ++ show tok

data Token = 
       TokenOpenBracket
     | TokenCloseBracket
     | TokenOpenParen
     | TokenCloseParen
     | TokenOpenBrace
     | TokenCloseBrace
     | TokenDashArrow
     | TokenEqualsArrow
     | TokenComma
     | TokenSemicolon
     | TokenPeriod
     | TokenBar
     | TokenEquals
     | TokenUnderscore
     | TokenAtSign
     | TokenPercent
     | TokenHash
     | TokenBackSlash
     | TokenDoubleColon
     | TokenConId String
     | TokenVarId String
     | TokenInteger Integer
     | TokenData
     | TokenForall
     | TokenClass
     | TokenWhere
     | TokenCase
     | TokenOf
     | TokenEOF
    deriving (Show)

isSmall :: Char -> Bool
isSmall '_' = True
isSmall c | isLower c = True
isSmall _ = False

isLarge :: Char -> Bool
isLarge = isUpper

isIdChar :: Char -> Bool
isIdChar c | isSmall c = True
isIdChar c | isLarge c = True
isIdChar c | isDigit c = True
isIdChar '\'' = True
isIdChar _ = False

doubles :: [(String, Token)]
doubles = [
    ("->", TokenDashArrow),
    ("=>", TokenEqualsArrow),
    ("::", TokenDoubleColon)
    ]

singles :: [(Char, Token)]
singles = [
    ('[', TokenOpenBracket),
    (']', TokenCloseBracket),
    ('(', TokenOpenParen),
    (')', TokenCloseParen),
    ('{', TokenOpenBrace),
    ('}', TokenCloseBrace),
    (',', TokenComma),
    (';', TokenSemicolon),
    ('.', TokenPeriod),
    ('|', TokenBar),
    ('=', TokenEquals),
    ('_', TokenUnderscore),
    ('@', TokenAtSign),
    ('%', TokenPercent),
    ('#', TokenHash),
    ('\\', TokenBackSlash)
    ]

keywords :: [(String, Token)]
keywords = [         
    ("data", TokenData),
    ("forall", TokenForall),
    ("class", TokenClass),
    ("where", TokenWhere),
    ("case", TokenCase),
    ("of", TokenOf)
    ]

failE :: String -> ParserMonad a
failE msg = do
    modify $ \ps -> ps { ps_error = Just msg}
    fail msg

-- advance a single column
single :: ParserMonad ()
single = modify $ \ps -> ps {ps_column = 1 + ps_column ps }

-- advance two columns
double :: ParserMonad ()
double = single >> single

-- advance many columns
many :: String -> ParserMonad ()
many = mapM_ (const single)

-- advance to the next line
newline :: ParserMonad ()
newline = modify $ \ps -> ps {ps_line = 1 + ps_line ps }

setText :: String -> ParserMonad ()
setText txt = modify $ \ps -> ps {ps_text = txt }

lexer :: (Token -> ParserMonad a) -> ParserMonad a
lexer output = do
  let odouble t r = double >> setText r >> output t
  let osingle t r = single >> setText r >> output t
  text <- gets ps_text
  case text of
      [] -> output TokenEOF
      (c1:c2:cs) | ([c1, c2] `elem` (map fst doubles)) ->
          odouble (fromJust (lookup [c1, c2] doubles)) cs
      (c:cs) | (c `elem` (map fst singles)) ->
          osingle (fromJust (lookup c singles)) cs
      ('\n':cs) -> newline >> setText cs >> lexer output
      (c:cs) | isSpace c -> single >> setText cs >> lexer output
      (c:cs) | isLarge c ->
          let (ns, rest) = span isIdChar cs
          in many (c:ns) >> setText rest >> (output $ TokenConId (c:ns))
      (c:cs) | isSmall c ->
          let (ns, rest) = span isIdChar cs
          in case (c:ns) of
              kw | kw `elem` (map fst keywords) ->
                  many kw >> setText rest >> output (fromJust (lookup kw keywords))
              id -> many id >> setText rest >> output (TokenVarId id)
      (c:cs) | isDigit c ->
          let (ns, rest) = span isDigit cs
          in many (c:ns) >> setText rest >> output (TokenInteger (read (c:ns)))
      cs -> failE $ "fail to lex: " ++ cs

parseDecs :: (Monad m) => String -> m [Dec]
parseDecs text =
    case (runState seri_decls (ParserState text 1 0 Nothing)) of
        (ds, ParserState _ _ _ Nothing) -> return ds
        (_, ParserState _ _ _ (Just msg)) -> fail msg


}

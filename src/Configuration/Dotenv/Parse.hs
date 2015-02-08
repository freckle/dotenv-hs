module Configuration.Dotenv.Parse (configParser) where

import Text.Parsec ((<|>), many, try, manyTill, char, anyChar)
import Text.Parsec.Combinator (eof)
import Text.Parsec.String (Parser)
import Text.ParserCombinators.Parsec.Char (space, newline, oneOf, noneOf)
import Text.ParserCombinators.Parsec.Prim (GenParser)

import Control.Applicative ((<*), (*>), (<$>))
import Data.Maybe (catMaybes)
import Control.Monad (liftM2)

-- | Returns a parser for a Dotenv configuration file.
-- Accepts key and value arguments separated by "=".
-- Comments are allowed on lines by themselves and on
-- blank lines.
configParser :: Parser [(String, String)]
configParser = catMaybes <$> many envLine


envLine :: Parser (Maybe (String, String))
envLine = (comment <|> blankLine) *> return Nothing
          <|> Just <$> configurationOptionWithArguments

blankLine :: Parser String
blankLine = many verticalSpace <* newline

configurationOptionWithArguments :: Parser (String, String)
configurationOptionWithArguments = liftM2 (,)
  (many space *> manyTill1 anyChar keywordArgSeparator)
  argumentParser

argumentParser :: Parser String
argumentParser = quotedArgument <|> unquotedArgument

quotedArgument :: Parser String
quotedArgument = quotedWith '\'' <|> quotedWith '\"'

unquotedArgument :: Parser String
unquotedArgument = manyTill anyChar
                   (comment <|> many verticalSpace <* endOfLineOrInput)

-- | Based on a commented-string parser in:
-- http://hub.darcs.net/navilan/XMonadTasks/raw/Data/Config/Lexer.hs
quotedWith :: Char -> Parser String
quotedWith c = char c *> many chr <* char c

  where chr = esc <|> noneOf [c]
        esc = escape *> char c

comment :: Parser String
comment = try (many verticalSpace *> char '#')
          *> manyTill anyChar endOfLineOrInput

endOfLineOrInput :: Parser ()
endOfLineOrInput = newline *> return () <|> eof

manyTill1 :: GenParser tok st a -> GenParser tok st end -> GenParser tok st [a]
manyTill1 p end = liftM2 (:) p (manyTill p end)

keywordArgSeparator :: Parser ()
keywordArgSeparator =
  many verticalSpace *> char '=' *> many verticalSpace *> return ()

escape :: Parser Char
escape = char '\\'

verticalSpace :: Parser Char
verticalSpace = oneOf " \t"

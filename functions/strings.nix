{lib, ...}:
with lib; {
  toSnakeCase = str:
    throwIfNot (isString str) "toSnakeCase does only accepts string values, but got ${typeOf str}" (
      let
        separators =
          splitStringBy (
            prev: curr:
              elem curr [
                "-"
                "_"
                " "
              ]
          )
          false
          str;

        parts = flatten (
          map (splitStringBy (
              prev: curr: match "[a-z]" prev != null && match "[A-Z]" curr != null
            )
            true)
          separators
        );
      in
        join "_" (map (addContextFrom str) (map toLower parts))
    );

  toPascalCase = str:
    throwIfNot (isString str) "toPascalCase does only accepts string values, but got ${typeOf str}"
    (
      let
        separators =
          splitStringBy (
            prev: curr:
              elem curr [
                "-"
                "_"
                " "
              ]
          )
          false
          str;

        parts = flatten (
          map (splitStringBy (
              prev: curr: match "[a-z]" prev != null && match "[A-Z]" curr != null
            )
            true)
          separators
        );
      in
        concatStrings (map (addContextFrom str) (map toSentenceCase parts))
    );

  toKebabCase = str:
    throwIfNot (isString str) "toKebabCase does only accepts string values, but got ${typeOf str}" (
      let
        separators =
          splitStringBy (
            prev: curr:
              elem curr [
                "-"
                "_"
                " "
              ]
          )
          false
          str;

        parts = flatten (
          map (splitStringBy (
              prev: curr: match "[a-z]" prev != null && match "[A-Z]" curr != null
            )
            true)
          separators
        );
      in
        join "-" (map (addContextFrom str) (map toLower parts))
    );
}

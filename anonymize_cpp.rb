#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"

class SimpleCppAnonymizer
  CPP_KEYWORDS = Set.new(%w[
    alignas alignof and and_eq asm auto bitand bitor bool break case catch char
    char8_t char16_t char32_t class compl concept const consteval constexpr constinit
    const_cast continue co_await co_return co_yield decltype default delete do double
    dynamic_cast else enum explicit export extern false float for friend goto if inline
    int long mutable namespace new noexcept not not_eq nullptr operator or or_eq private
    protected public register reinterpret_cast requires return short signed sizeof static
    static_assert static_cast struct switch template this thread_local throw true try
    typedef typeid typename union unsigned using virtual void volatile wchar_t while xor xor_eq

    # よく出るC系
    FILE NULL size_t stdin stdout stderr
  ])

  # 最初はここに「変えたくない名前」を少しだけ入れておく
  RESERVED_IDENTIFIERS = Set.new(%w[
    main
    printf fprintf sprintf snprintf
    scanf fscanf sscanf
    malloc calloc realloc free
    memcpy memmove memset
    strcmp strlen
    std cout cin cerr endl
  ])

  IDENTIFIER_REGEX = /\b[A-Za-z_][A-Za-z0-9_]*\b/

  def initialize
    @mapping = {}
    @counter = 1
  end

  attr_reader :mapping

  def anonymize(code)
    protected_parts = []
    masked = protect_strings_comments_and_chars(code, protected_parts)

    identifiers = masked.scan(IDENTIFIER_REGEX).uniq
    identifiers.each do |name|
      next if skip_identifier?(name)

      @mapping[name] ||= next_symbol_name
    end

    replaced = masked.gsub(IDENTIFIER_REGEX) do |name|
      @mapping.fetch(name, name)
    end

    restore_protected_parts(replaced, protected_parts)
  end

  private

  def skip_identifier?(name)
    CPP_KEYWORDS.include?(name) || RESERVED_IDENTIFIERS.include?(name)
  end

  def next_symbol_name
    name = format("sym_%03d", @counter)
    @counter += 1
    name
  end

  def protect_strings_comments_and_chars(code, protected_parts)
    result = +""
    i = 0

    while i < code.length
      # // line comment
      if code[i, 2] == "//"
        j = i + 2
        j += 1 while j < code.length && code[j] != "\n"
        result << store_placeholder(code[i...j], protected_parts)
        i = j

      # /* block comment */
      elsif code[i, 2] == "/*"
        j = i + 2
        while j < code.length - 1 && code[j, 2] != "*/"
          j += 1
        end
        j += 2 if j < code.length
        result << store_placeholder(code[i...j], protected_parts)
        i = j

      # "string literal"
      elsif code[i] == '"'
        j = i + 1
        while j < code.length
          if code[j] == "\\"
            j += 2
          elsif code[j] == '"'
            j += 1
            break
          else
            j += 1
          end
        end
        result << store_placeholder(code[i...j], protected_parts)
        i = j

      # 'char literal'
      elsif code[i] == "'"
        j = i + 1
        while j < code.length
          if code[j] == "\\"
            j += 2
          elsif code[j] == "'"
            j += 1
            break
          else
            j += 1
          end
        end
        result << store_placeholder(code[i...j], protected_parts)
        i = j

      else
        result << code[i]
        i += 1
      end
    end

    result
  end

  def store_placeholder(text, protected_parts)
    index = protected_parts.length
    protected_parts << text
    "__PROTECTED_#{index}__"
  end

  def restore_protected_parts(code, protected_parts)
    code.gsub(/__PROTECTED_(\d+)__/) do
      protected_parts[Regexp.last_match(1).to_i]
    end
  end
end

def main
  if ARGV.size != 2
    warn "Usage: ruby anonymize_cpp.rb input.cpp output.cpp"
    exit 1
  end

  input_path = ARGV[0]
  output_path = ARGV[1]

  code = File.read(input_path, encoding: "UTF-8")
  anonymizer = SimpleCppAnonymizer.new
  result = anonymizer.anonymize(code)

  File.write(output_path, result)

  map_path = "#{output_path}.map.txt"
  File.open(map_path, "w:utf-8") do |f|
    anonymizer.mapping.each do |original, anonymized|
      f.puts "#{original} => #{anonymized}"
    end
  end

  puts "Written: #{output_path}"
  puts "Mapping: #{map_path}"
end

main if __FILE__ == $PROGRAM_NAME
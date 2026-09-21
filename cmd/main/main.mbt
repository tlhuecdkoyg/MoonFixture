///|
suberror InputError {
  InputError(String)
}

///|
async fn read_text(reader : &@io.Reader, limit : Int) -> String {
  let chunks : Array[Bytes] = []
  let mut total = 0
  for ;; {
    let size = (limit - total).min(65536).max(1)
    match reader.read_some(max_len=size) {
      None => break
      Some(bytes) => {
        if bytes.length() > limit - total {
          raise InputError("Input exceeds --max-input bytes")
        }
        total += bytes.length()
        chunks.push(bytes)
      }
    }
  }
  let bytes = FixedArray::make(total, b'\x00')
  let mut offset = 0
  for chunk in chunks {
    for byte in chunk {
      bytes[offset] = byte
      offset += 1
    }
  }
  @utf8.decode(Bytes::from_iter(bytes.iter()))
}

///|
async fn load(path : String, limit : Int) -> String {
  if path == "-" {
    return read_text(@stdio.stdin, limit)
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.size() > limit.to_int64() {
    raise InputError("Input file exceeds --max-input bytes")
  }
  read_text(file, limit)
}

///|
async fn run() -> Int {
  let args = @env.args()
  let options = match @cli.parse_args(args[1:].to_owned()) {
    Ok(options) => options
    Err(message) => {
      @stdio.stderr.write(
        "MoonFixture: " + message + "\nUse --help for usage.\n",
      )
      return 2
    }
  }
  let input = if options.command == "help" || options.command == "version" {
    ""
  } else {
    load(options.input, options.max_input)
  }
  let model_text = match options.model_file {
    Some(path) => load(path, options.max_input)
    None => ""
  }
  let output = @cli.execute(input, options, model_text~)
  for diagnostic in output.diagnostics {
    @stdio.stderr.write("MoonFixture: " + diagnostic + "\n")
  }
  if !output.text.is_empty() {
    let text = output.text +
      (if output.text.has_suffix("\n") { "" } else { "\n" })
    match options.output {
      None | Some("-") => @stdio.stdout.write(text)
      Some(path) => {
        if @fs.exists(path) {
          let resolved = @fs.realpath(path)
          if options.input != "-" &&
            !options.input.is_empty() &&
            resolved == @fs.realpath(options.input) {
            raise InputError("Output cannot replace the input")
          }
          if options.model_file is Some(model_path) &&
            resolved == @fs.realpath(model_path) {
            raise InputError("Output cannot replace the validation model")
          }
        }
        @fs.write_file(
          path,
          text,
          create_mode=if options.overwrite {
            CreateOrTruncate
          } else {
            CreateNew
          },
        )
      }
    }
  }
  output.exit_code
}

///|
async fn main {
  let code = run() catch {
    error => {
      @stdio.stderr.write("MoonFixture I/O error: \{error}\n")
      2
    }
  }
  @sys.exit(code)
}

(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Cmdliner
open Rresult
open Functoria_misc

let global_option_section = "COMMON OPTIONS"

let help_sections = [
  `S global_option_section;
  `P "These options are common to all commands.";
]

(* Helpers *)
let mk_flag ?(section=global_option_section) flags doc =
  let doc = Arg.info ~docs:section ~doc flags in
  Arg.(value & flag & doc)

let term_info title ~doc ~man =
  let man = man @ help_sections in
  Term.info ~sdocs:global_option_section ~doc ~man title

let no_opam =
  mk_flag ["no-opam"]
    "Do not manage the OPAM configuration. \
     This will result in dependent libraries not being automatically \
     installed during the configuration phase."

let no_opam_version_check =
  mk_flag ["no-opam-version-check"] "Bypass the OPAM version check."

let no_depext =
  mk_flag ["no-depext"] "Skip installation of external dependencies."

let full_eval =
  mk_flag ["eval"]
    "Fully evaluate the graph before showing it. \
     By default, only the keys that are given on the command line are \
     evaluated."

let dot =
  mk_flag ["dot"]
    "Output a dot description. \
     If no output file is given,  it will display the dot file using the command \
     given to $(b,--dot-command)."

let dotcmd =
  let doc =
    Arg.info ~docs:global_option_section ~docv:"COMMAND" [ "dot-command" ]
      ~doc:"Command used to show a dot file. This command should accept a \
            dot file on its standard input."
  in
  Arg.(value & opt string "xdot" & doc)

let file =
  let doc =
    Arg.info ~docs:global_option_section ~docv:"CONFIG_FILE" ["f"; "file"]
      ~doc:"Configuration file. If not specified, the current directory will \
            be scanned. If one file named $(b,config.ml) is found, that file \
            will be used. If no files or multiple configuration files are \
            found, this will result in an error unless one is explicitly \
            specified on the command line."
  in
  Arg.(value & opt (some file) None & doc)

let output =
  let doc =
    Arg.info ~docs:global_option_section ~docv:"FILE" ["o"; "output"]
      ~doc:"File where to output description or dot representation."
  in
  Arg.(value & opt (some string) None & doc)

let color =
  let enum = ["auto", None; "always", Some `Ansi_tty; "never", Some `None] in
  let color = Arg.enum enum in
  let alts = Arg.doc_alts_enum enum in
  let doc = Arg.info ["color"] ~docs:global_option_section ~docv:"WHEN"
      ~doc:(Fmt.strf "Colorize the output. $(docv) must be %s." alts)
  in
  Arg.(value & opt color None & doc)

let verbose =
  let doc =
    Arg.info ~docs:global_option_section ~doc:"Be verbose" ["verbose";"v"]
  in
  Arg.(value & flag_all doc)

let init_log = function
  | []  -> Functoria_misc.Log.(set_level WARN)
  | [_] -> Functoria_misc.Log.(set_level INFO)
  | _   -> Functoria_misc.Log.(set_level DEBUG)

let init_format color =
  let i = Terminfo.columns () in
  Functoria_misc.Log.set_color color;
  Format.pp_set_margin Format.std_formatter i;
  Format.pp_set_margin Format.err_formatter i;
  Fmt_tty.setup_std_outputs ?style_renderer:color ()

let load_verbose () =
  let v = match Term.eval_peek_opts verbose with
    | _, `Ok v -> v
    | _ -> []
  in
  init_log v

let load_color () =
  (* This is ugly but we really want the color options to be set
     before calling [load_config]. *)
  let c = match Term.eval_peek_opts color with
    | _, `Ok color -> color
    | _ -> None
  in
  init_format c

let load_fully_eval () =
  match snd @@ Term.eval_peek_opts full_eval with
  | `Ok b -> b
  | _ -> false

type 'a subcommand_info = {
  doc: string;
  man: Manpage.block list;
  opts: 'a Term.t;
}

(** Subcommand information *)
let configure_info = {
  doc = "Configure a $(mname) application.";
  man = [
    `S "DESCRIPTION";
    `P "The $(b,configure) command initializes a fresh $(mname) application."
    ];
  opts = Term.(pure (fun a b c -> (a, b, c))
               $ no_opam
               $ no_opam_version_check
               $ no_depext)
}

let describe_info = {
  doc = "Describe a $(mname) application.";
  man = [
    `S "DESCRIPTION";
    `P "The $(b,describe) command describes the configuration of a \
        $(mname) application.";
    `P "The dot output contains the following elements:";
    `Noblank;
    `I ("If vertices",
        "Represented as circles. Branches are dotted, and the default branch \
         is in bold.");
    `Noblank;
    `I ("Configurables",
        "Represented as rectangles. The order of the output arrows is \
         the order of the functor arguments.");
    `Noblank;
    `I ("Data dependencies",
        "Represented as dashed arrows.");
    `Noblank;
    `I ("App vertices",
        "Represented as diamonds. The bold arrow is the functor part.");
  ];
  opts = Term.(pure (fun a b c -> (a, b, c))
              $ output
              $ dotcmd
              $ dot);
}

let build_info =
  let doc = "Build a $(mname) application." in
  { doc;
    man = [
      `S "DESCRIPTION";
      `P doc;
    ];
    opts = Term.pure () }

let clean_info =
  let doc = "Clean the files produced by $(mname) for a given application." in
  { doc;
    man = [
      `S "DESCRIPTION";
      `P doc;
    ];
    opts = Term.pure (); }

module Make (Config: Functoria_sigs.CONFIG) = struct
  let load_config () =
    let c = match Term.eval_peek_opts file with
      | _, `Ok config -> config
      | _ -> None
    in
    let _ = Term.eval_peek_opts Config.base_context in
    Config.load c

  let config = Lazy.from_fun load_config
  let set_color  = Lazy.from_fun load_color
  let set_verbose = Lazy.from_fun load_verbose

  let with_config ?(with_eval=false) ?(with_required=false) f options =
    Lazy.force set_color;
    Lazy.force set_verbose;
    let handle_error = function
      | Ok x    -> x
      | Error s -> Log.fatal "%s" s
    in
    match Lazy.force config with
    | Ok t ->
      let if_context = Config.if_context t in
      let partial = with_eval && not @@ load_fully_eval () in
      let term = match Term.eval_peek_opts if_context with
        | Some context, _ ->
          Term.app f @@ Config.eval ~with_required ~partial context t
        | _, _ ->
          (* If peeking has failed, this should always fail too, but with
             a good error message. *)
          Term.app f @@ Config.eval ~with_required ~partial Functoria_key.empty_context t
      in

      let t =
        Term.(pure (fun _ _ _ -> handle_error) $ verbose $ color $ file
          $ (term $ options))
      in
      if with_eval
      then Term.(pure (fun _ t -> t) $ full_eval $ t)
      else t

    | Error err -> Log.fatal "%s" err
    (* We fail early here to avoid reporting lookup errors. *)

  (* CONFIGURE *)
  let configure () =
    let configure info (no_opam, no_opam_version, no_depext) =
      Config.configure info ~no_opam ~no_depext ~no_opam_version in
    (with_config ~with_required:true (Term.pure configure) configure_info.opts,
     term_info "configure" ~doc:configure_info.doc ~man:configure_info.man)

  (* DESCRIBE *)
  let describe () =
    let describe info (output, dotcmd, dot) =
      Config.describe ~dotcmd ~dot ~output info in
    (with_config ~with_eval:true (Term.pure describe) describe_info.opts,
     term_info "describe" ~doc:describe_info.doc ~man:describe_info.man)

  (* BUILD *)
  let build () =
    let build info () = Config.build info in
    (with_config (Term.pure build) build_info.opts,
     term_info "build" ~doc:build_info.doc ~man:build_info.man)

  (* CLEAN *)
  let clean () =
    let clean info () = Config.clean info in
    (with_config (Term.pure clean) clean_info.opts,
     term_info "clean" ~doc:clean_info.doc ~man:clean_info.man)

  (* HELP *)
  let help =
    let doc = "Display help about $(mname) commands." in
    let man = [
      `S "DESCRIPTION";
      `P "Prints help.";
      `P "Use `$(mname) help topics' to get the full list of help topics.";
    ] in
    let topic =
      let doc = Arg.info [] ~docv:"TOPIC" ~doc:"The topic to get help on." in
      Arg.(value & pos 0 (some string) None & doc )
    in
    let help verbose color man_format cmds topic _keys =
      init_log verbose;
      init_format color;
      match topic with
      | None       -> `Help (`Pager, None)
      | Some topic ->
        let topics = "topics" :: cmds in
        let conv, _ = Arg.enum (List.rev_map (fun s -> (s, s)) topics) in
        match conv topic with
        | `Error e -> `Error (false, e)
        | `Ok t when t = "topics" -> List.iter print_endline cmds; `Ok ()
        | `Ok t -> `Help (man_format, Some t) in
    let term =
      Term.(pure help $ verbose $ color $ Term.man_format $ Term.choice_names
            $ topic $ Config.base_context)
    in
    Term.ret term, Term.info "help" ~doc ~man

  let default =
    let doc = "The $(mname) application builder" in
    let man = [
      `S "DESCRIPTION";
      `P "The $(mname) application builder. It glues together a set of \
          libraries and configuration (e.g. network and storage) into a \
          standalone unikernel or UNIX binary.";
      `P "Use either $(b,$(mname) <command> --help) or \
          $(b,($mname) help <command>) for more information on a specific \
          command.";
    ] @  help_sections
    in
    let usage verbose color =
      init_log verbose;
      init_format color;
      `Help (`Plain, None)
    in
    let term = Term.(ret (pure usage $ verbose $ color)) in
    term,
    Term.info Config.name
      ~version:Config.version
      ~sdocs:global_option_section
      ~doc
      ~man

  let commands () = [
    configure ();
    describe ();
    build ();
    clean ();
    help;
  ]

  let () =
    try match Term.eval_choice ~catch:false default (commands ()) with
      | `Error _ -> exit 1
      | _ -> ()
    with
    | Functoria_misc.Log.Fatal s ->
      Log.show_error "%s" s ;
      exit 1
end

let initialize (module Config:Functoria_sigs.CONFIG) =
 let module M = Make(Config) in ()

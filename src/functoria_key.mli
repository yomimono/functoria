(*
 * Copyright (c) 2015 Nicolas Ojeda Bar <n.oje.bar@gmail.com>
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

(** Support for setting configuration parameters via the command-line.

    [Functoria_key] is used by the [Functoria] and [Functoria_tool] modules to:

    - Construct [Cmdliner.Term.t]'s corresponding to used configuration keys in
      order to be able to set them at compile-time (see {!Main.configure}).

    - Generate a [bootvar.ml] file during configuration containing necessary
      code to do the same at run-time. *)

module Desc : sig

  type 'a parser = string -> [ `Ok of 'a | `Error of string ]
  type 'a printer = Format.formatter -> 'a -> unit
  type 'a converter = 'a parser * 'a printer

  type 'a t

  val serializer : 'a t -> Format.formatter -> 'a -> unit
  val description :  'a t -> string
  val converter : 'a t -> 'a converter

  val create :
    serializer:(Format.formatter -> 'a -> unit) ->
    converter:'a converter ->
    description:string ->
    'a t

  val string : string t
  val list : 'a t -> 'a list t


end

module Doc : sig

  type t

  val create : ?docs:string -> ?docv:string -> ?doc:string -> string list -> t
  val to_cmdliner : t -> Cmdliner.Arg.info
  val emit : Format.formatter -> t -> unit

end



type stage = [
  | `Configure
  | `Run
  | `Both
]

type 'a key
(** The type of configuration keys that can be set on the command-line. *)

val create : ?doc:string -> ?stage:stage -> default:'a -> string -> 'a Desc.t -> 'a key
(** [create ~doc ~stage ~default name desc] creates a new configuration key with
    docstring [doc], default value [default], name [name] and type descriptor
    [desc].  It is an error to use more than one key with the same [name]. *)

val create_raw : doc:Doc.t -> stage:stage -> default:'a -> string -> 'a Desc.t -> 'a key

type t = V : 'a key -> t

val compare : t -> t -> int
(** [compare k1 k2] is [compare (name k1) (name k2)]. *)

module Set : Set.S with type elt = t


val name : t -> string

val ocaml_name : t -> string
(** [name k] is just [ocamlify k.name].  Two keys [k1] and [k2] are considered
    equal if [name k1 = name k2]. *)

val stage : t -> stage

val is_runtime : t -> bool
val is_configure : t -> bool


val term_key : t -> unit Cmdliner.Term.t
(** [term_key k] is a [Cmdliner.Term.t] that, when evaluated, sets the value
    of the the key [k]. *)

val term : ?stage:stage -> Set.t -> unit Cmdliner.Term.t
(** [term l] is a [Cmdliner.Term.t] that, when evaluated, sets the value of the
    the keys in [l]. *)

type 'a value

val pure : 'a -> 'a value
val value : 'a key -> 'a value
val app : ('a -> 'b) value -> 'a value -> 'b value
val ($) : ('a -> 'b) value -> 'a value -> 'b value

val deps : 'a value -> Set.t

val peek : 'a value -> 'a option

val eval : 'a value -> 'a


val serialize : Format.formatter -> t -> unit
(** [serialize () k] returns a string [s] such that if [k.v] is [V (_, r)],
    then evaluating the contents of [s] will produce the value [!r]. *)

val describe : Format.formatter -> t -> unit
(** [describe () k] returns a string [s] such that if [k.v] is [V (d, _)],
    then evaluating the contents of [s] will produce the value [d]. *)

val emit : Format.formatter -> t -> unit



exception Illegal of string

val ocamlify : string -> string
(** [ocamlify s] returns a valid OCaml identifier from similar to [s].
    Concretely, [ocamlify s] is the string that results from removing all
    characters outside of ['a'-'z''A'-'Z''0''9''_''-'], and replacing '-' with
    '_'.  If the resulting string starts with a digit or is empty then it raises
    [Illegal s]. *)

(**/*)

val get : 'a key -> 'a
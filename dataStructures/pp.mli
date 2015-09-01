open Format

val listi :
  ?trailing:(formatter -> unit) ->
  (formatter -> unit) -> (int -> formatter -> 'a -> unit) ->
  formatter -> 'a list -> unit
val list :
  ?trailing:(formatter -> unit) ->
  (formatter -> unit) -> (formatter -> 'a -> unit) ->
  formatter -> 'a list -> unit
val set :
  ?trailing:(formatter -> unit) ->
  ('b -> 'a list) -> (formatter -> unit) -> (formatter -> 'a -> unit) ->
  formatter -> 'b -> unit
val hashtbl : (formatter -> unit) -> (formatter -> 'a * 'b -> unit) ->
	  formatter -> ('a,'b) Hashtbl.t -> unit

val option : (formatter -> 'a -> unit) -> formatter -> 'a option -> unit
val bottom : formatter -> unit
val nu : formatter -> unit
val comma : formatter -> unit
val colon : formatter -> unit
val space : formatter -> unit
val cut : formatter -> unit
val empty : formatter -> unit

val array :
  ?trailing:(formatter -> unit) ->
  (formatter -> unit) -> (int -> formatter -> 'a -> unit) ->
  formatter -> 'a array -> unit
val plain_array : (formatter -> 'a -> unit) -> formatter -> 'a array -> unit

val error : (formatter -> 'a -> unit) -> 'a Location.annot -> unit

val list_to_string : (unit -> string) ->
		     (unit -> 'a -> string) -> unit -> 'a list -> string
val set_to_string : ('b -> 'a list) -> (unit -> string) ->
		    (unit -> 'a -> string) -> unit -> 'b -> string

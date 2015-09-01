let int_compare (x: int) y = Pervasives.compare x y
let int_pair_compare (p,q) (p',q') =
  let o = int_compare p p' in
  if o = 0 then int_compare q q' else o

module StringMap = MapExt.Make (String)
module IntMap = MapExt.Make (struct type t = int let compare = int_compare end)
module IntSet =
  Set_patched.Make (struct type t = int let compare = int_compare end)
module Int2Map =
  MapExt.Make (struct type t = int*int let compare = int_pair_compare end)
module StringSet = Set.Make (String)
module Int2Set =
  Set.Make (struct type t = int*int let compare = int_pair_compare end)
module Int3Set = Set.Make (struct type t = int*int*int let compare= compare end)
module StringIntMap =
  MapExt.Make (struct type t = (string * int) let compare = compare end)

module DynArray = DynamicArray.DynArray(LargeArray.GenArray)

module Injection : sig
  type t
  val compare : t -> t -> int
  (** [empty expected_size inj_address] *)
  val empty : int -> int * int -> t
  val add : int -> int -> t -> t
  val flush : t -> int * int -> t

  val find : int -> t -> int
  val root_image : t -> (int * int) option
  val get_coordinate : t -> (int * int)
  val set_address :  int -> t -> unit
  val get_address : t -> int
  val is_trashed : t -> bool

  exception Clashing
  val codomain : t -> int IntMap.t * IntSet.t -> int IntMap.t * IntSet.t
  val to_map : t -> int IntMap.t * IntSet.t

  val fold : (int -> int -> 'a -> 'a) -> t -> 'a -> 'a
  val print : Format.formatter -> t -> unit
  val print_coord : Format.formatter -> t -> unit
end = struct
  type t = {map : (int,int) Hashtbl.t ;
	    mutable address : int option ;
	    coordinate : (int*int)}

    exception Found of (int*int)
    let root_image phi =
      try (Hashtbl.iter (fun i j -> raise (Found (i,j))) phi.map ; None)
      with Found (i,j) -> Some (i,j)

    let set_address addr phi = phi.address <- Some addr

    let get_address phi =
      match phi.address with Some a -> a | None -> raise Not_found
    let get_coordinate phi = phi.coordinate

    let to_map phi =
      Hashtbl.fold (fun i j (map,cod) -> (IntMap.add i j map,IntSet.add j cod))
		   phi.map (IntMap.empty,IntSet.empty)
    let is_trashed phi = match phi.address with Some (-1) -> true | _ -> false

    let add i j phi = Hashtbl.replace phi.map i j ; phi
    let find i phi = Hashtbl.find phi.map i
    let empty n (mix_id,cc_id) =
      {map = Hashtbl.create n ; address = None ; coordinate = (mix_id,cc_id)}
    let flush phi (var_id,cc_id) =
      {phi with address = None ; coordinate = (var_id,cc_id)}

    let compare phi psi =
      let o = int_pair_compare phi.coordinate psi.coordinate in
      if o = 0 then match phi.address, psi.address with
		    | Some a, Some a' -> int_compare a a'
		    | _, _ -> invalid_arg "Injection.compare"
      else o

    let fold f phi cont = Hashtbl.fold f phi.map cont

    exception Clashing
    let codomain phi (inj,cod) =
      Hashtbl.fold
	(fun i j (map,set) ->
	 if IntSet.mem j set then raise Clashing
	 else (IntMap.add i j map,IntSet.add j set))
	phi.map (inj,cod)

    let print f phi =
      Format.fprintf
	f "[%a]" (Pp.hashtbl
		    Pp.comma (fun f (i,j) -> Format.fprintf f "%i -> %i" i j))
	phi.map

    let print_coord f phi =
      let a = get_address phi and (m,c) = get_coordinate phi in
      Format.fprintf f "(%d,%d,%d)" m c a
  end

module InjProduct =
  struct
    type t = {elements : Injection.t array ;
	      mutable address : int option ;
	      coordinate : int ;
	      signature : int array}
    type key = int array
		   
    let allocate phi addr = phi.address <- Some addr
						
    let get_address phi = match phi.address with Some a -> a | None -> raise Not_found
    let get_coordinate phi = phi.coordinate
			       
    let add cc_id inj injprod =
      try
	injprod.elements.(cc_id) <- inj ;
	let root = (function Some (_,u) -> u
			   | None -> invalid_arg "InjProduct.add")
		     (Injection.root_image inj) in
	injprod.signature.(cc_id) <- root
      with Invalid_argument msg -> invalid_arg ("InjProduct.add: "^msg)
					       
    let is_trashed injprod =
      match injprod.address with Some (-1) -> true | _ -> false
							    
    exception False
		
    let is_complete injprod =
      try
	(Array.iter (fun inj_i ->
		      let a,_ = Injection.get_coordinate inj_i in
		      if a<0 then raise False else ()) injprod.elements ; true)
      with False -> false
		      
    let size injprod = Array.length injprod.elements
				    
    let find i injprod =
      try injprod.elements.(i) with Invalid_argument _ -> raise Not_found
		
    let create n mix_id = {elements = Array.make n (Injection.empty 0 (-1,-1)) ; address = None ; coordinate = mix_id ; signature = Array.make n (-1)}
		
    let equal phi psi =
      try
	(Array.length phi.signature) = (Array.length psi.signature) &&
	  (
	    Array.iteri (fun cc_id u -> if u <> psi.signature.(cc_id) then raise False)
			phi.signature ;
	    true)
      with False -> false
		
    let get_key phi = phi.signature
		
    let compare phi psi =
      let o = int_compare phi.coordinate psi.coordinate in
      if o = 0 then
	try
	  let a = get_address phi in
	  let a'= get_address psi in
	  int_compare a a'
	with Not_found -> invalid_arg "Injection.compare"
      else o

    let fold_left f cont phi = Array.fold_left f cont phi.elements
		
    let print f phi = Pp.plain_array Injection.print f phi.elements
  end

module InjectionHeap =
  Heap.Make
    (struct
      type t = Injection.t
      let allocate = fun inj i -> Injection.set_address i inj
      let get_address inj = Injection.get_address inj
    end)

module InjProdHeap = SafeHeap.Make(InjProduct) 

module InjProdSet = Set.Make(InjProduct)

module Counter =
  struct
    type t = {
      mutable time:float ;
      mutable events:int ;
      mutable null_events:int ;
      mutable cons_null_events:int;
      mutable perturbation_events:int ;
      mutable null_action:int ;
      mutable last_tick : (int * float) ;
      mutable initialized : bool ;
      mutable ticks : int ;
      stat_null : int array ;
      init_time : float ;
      init_event : int ;
      max_time : float option ;
      max_events : int option ;
      dE : int option ;
      dT : float option ;
      mutable stop : bool
    }

    let stop c = c.stop
    let inc_tick c = c.ticks <- c.ticks + 1
    let time c = c.time
    let event c = c.events
    let null_event c = c.null_events
    let null_action c = c.null_action
    let is_initial c = c.time = c.init_time
    let inc_time c dt = c.time <- (c.time +. dt)
    let inc_events c =c.events <- (c.events + 1)
    let inc_null_events c = c.null_events <- (c.null_events + 1)
    let inc_consecutive_null_events c =
      (c.cons_null_events <- c.cons_null_events + 1)
    let inc_null_action c = c.null_action <- (c.null_action + 1)
    let	reset_consecutive_null_events c = c.cons_null_events <- 0
    let check_time c =
      match c.max_time with None -> true | Some max -> c.time < max
    let check_output_time c ot =
      match c.max_time with None -> true | Some max -> ot < max
    let check_events c =
      match c.max_events with None -> true | Some max -> c.events < max
    let one_constructive_event c dt =
      let () = reset_consecutive_null_events c in
      let () = inc_events c in
      let () = inc_time c dt in
      check_time c && check_events c
    let one_null_event c dt =
      let () = inc_null_events c in
      let () = inc_consecutive_null_events c in
      let () = inc_time c dt in
      check_time c && check_events c

    let dT c = c.dT
    let dE c = c.dE
    let last_tick c = c.last_tick
    let set_tick c (i,x) = c.last_tick <- (i,x)

    let last_increment c = let _,t = c.last_tick in (c.time -. t)

    let compute_dT points mx_t =
      if points <= 0 then None else
	match mx_t with
	| None -> None
	| Some max_t -> Some (max_t /. (float_of_int points))

    let compute_dE points mx_e =
      if points <= 0 then None else
	match mx_e with
	| None -> None
	| Some max_e ->
	   Some (max (max_e / points) 1)

    let tick f counter time event =
      let () =
	if not counter.initialized then
	  let c = ref !Parameter.progressBarSize in
	  while !c > 0 do
	    Format.pp_print_string f "_" ;
	    c:=!c-1
	  done ;
	  Format.pp_print_newline f () ;
	  counter.initialized <- true
      in
      let last_event,last_time = counter.last_tick in
      let n_t =
	match counter.max_time with
	| None -> 0
	| Some tmax ->
	   int_of_float
	     ((time -. last_time) *.
		(float_of_int !Parameter.progressBarSize) /. tmax)
      and n_e =
	match counter.max_events with
	| None -> 0
	| Some emax ->
	   if emax = 0 then 0
	   else
	     let nplus =
	       (event * !Parameter.progressBarSize) / emax in
             let nminus =
	       (last_event * !Parameter.progressBarSize) / emax in
             nplus-nminus
      in
      let n = ref (max n_t n_e) in
      if !n>0 then set_tick counter (event,time) ;
      while !n > 0 do
	Format.fprintf f "%c" !Parameter.progressBarSymbol ;
	if !Parameter.eclipseMode then Format.pp_print_newline f ();
	inc_tick counter ;
	n:=!n-1
      done;
      Format.pp_print_flush f ()

    let stat_null i c =
      try c.stat_null.(i) <- c.stat_null.(i) + 1
      with _ -> invalid_arg "Invalid null event identifier"

    let create nb_points init_t init_e mx_t mx_e =
      let dE =
	compute_dE nb_points (Tools.option_map (fun x -> x - init_e) mx_e) in
      let dT = match dE with
	  None ->
	  compute_dT nb_points (Tools.option_map (fun x -> x -. init_t) mx_t)
	| Some _ -> None
      in
      {time = init_t ;
       events = init_e ;
       null_events = 0 ;
       cons_null_events = 0;
       stat_null = Array.init 6 (fun _ -> 0) ;
       perturbation_events = 0;
       null_action = 0 ;
       max_time = mx_t ;
       max_events = mx_e ;
       last_tick = (init_e,init_t);
       dE = dE ;
       dT = dT ;
       init_time = init_t ;
       init_event = init_e ;
       initialized = false ;
       ticks = 0 ;
       stop = false
      }
  end

module Palette:
	sig
	  type t
	  type color = (float*float*float)
	  val find : int -> t -> color
	  val add : int -> color -> t -> t
	  val mem : int -> t -> bool
	  val empty : t
	  val new_color : unit -> color
	  val grey : int -> string
	  val string_of_color : color -> string
	end =
	struct
	  type color = (float*float*float)
	  type t = color IntMap.t
	  let find = IntMap.find
	  let add = IntMap.add
	  let mem = IntMap.mem
	  let empty = IntMap.empty
	  let new_color () = Random.float 1.0,Random.float 1.0,Random.float 1.0
	  let grey d = if d > 16 then "black" else ("gray"^(string_of_int (100-6*d)))
	  let string_of_color (r,g,b) = String.concat "," (List.rev_map string_of_float [b;g;r])
	end

let tick_stories f n_stories (init,last,counter) =
  let () =
    if not init then
      let c = ref !Parameter.progressBarSize in
      let () = Format.pp_print_newline f () in
      while !c > 0 do
	Format.pp_print_string f "_" ;
	c:=!c-1
      done ;
      Format.pp_print_newline f ()
  in
  let nc = (counter * !Parameter.progressBarSize) / n_stories in
  let nl = (last * !Parameter.progressBarSize) / n_stories in
  let n = nc - nl in
  let rec aux n =
    if n<=0 then ()
    else
      let () = Format.fprintf f "%c" (!Parameter.progressBarSymbol) in
      let () = if !Parameter.eclipseMode then Format.pp_print_newline f () in
      aux (n-1)
  in
  let () = aux n in
  let _ =  Format.pp_print_flush f () in
  (true,counter,counter+1)

type 'a simulation_info = (* type of data to be given with obersables for story compression (such as date when the obs is triggered*)
    {
      story_id: int ; 
      story_time: float ;
      story_event: int ;
      profiling_info: 'a; 
    }

let update_profiling_info a info = 
  { 
    story_id = info.story_id ;
    story_time = info.story_time ;
    story_event = info.story_event ;
    profiling_info = a}

let compare_profiling_info info1 info2 = 
  match info1,info2
  with 
    | None,None -> 0
    | None,Some _ -> -1
    | Some _,None -> +1
    | Some info1,Some info2 -> 
      compare info1.story_id info2.story_id 

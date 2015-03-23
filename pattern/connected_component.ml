open Mods

type node = int * int * int (** (cc_id,type_id,node_id) *)
type link = UnSpec | Free | Link of int * int (** node_id, site_id *)

(** The link of site k of node i is stored in links(i).(k).

The internal state of site k of node i is store in internals(i).(k). A
negative number means UnSpec. *)
type cc = {
  id: int;
  nodes_by_type: int list array;
  links: link array IntMap.t;
  internals: int array IntMap.t;
}
type t = cc

type edge = ToNode of int * int | ToNew of int * int
	    | ToNothing | ToInternal of int
type son = {
  extra_edge: ((int*int)*edge);
  dst: int (** t.id *);
  inj: int array;
  above_obs: int list;
}

type point = {
  cc: t;
  is_obs: bool;
  fathers: int (** t.id *) list;
  sons: son list;
}

type work = {
  sigs: Signature.s;
  cc_env: point IntMap.t;
  reserved_id: int list array;
  used_id: int list array;
  free_id: int;
  cc_id: int;
  cc_links: link array IntMap.t;
  cc_internals: int array IntMap.t;
  dangling: node;
}

(** Errors *)
let print_bot f = Format.pp_print_string f "\xE2\x8A\xA5"
let print_site ?sigs (cc,agent,i) f id =
  match sigs with
  | Some sigs ->
     Signature.print_site sigs agent f id
  | None -> Format.fprintf f "cc%in%is%i" cc i id
let print_node ?sigs f (cc,ty,i) =
  match sigs with
  | Some sigs -> Format.fprintf f "%a/*%i*/" (Signature.print_agent sigs) ty i
  | None -> Format.fprintf f "cc%in%i" cc i
let print_internal ?sigs (_,agent,_) site f id =
  match sigs with
  | Some sigs ->
     Signature.print_site_internal_state sigs agent site f (Some id)
  | None -> Format.pp_print_int f id

let already_specified ?sigs x i =
  ExceptionDefn.Malformed_Decl
    (Term.with_dummy_pos
       (Format.asprintf "Site %a of agent %a already specified"
			(print_site ?sigs x) i (print_node ?sigs) x))

let dangling_node ?sigs x =
  ExceptionDefn.Malformed_Decl
    (Term.with_dummy_pos
       (Format.asprintf
	  "Cannot proceed because last declared agent %a%a" (print_node ?sigs) x
	  Format.pp_print_string " is not linked to its connected component."))

let equal max_id cc1 cc2 =
  let always_equal_min_but_not_null _ p l1 l2 =
    match p with
    | None -> None
    | Some (l,_,_) ->
       let l' = List.length l1 in
       if l' <> List.length l2 then None
       else if l = 0 || (l' > 0 && l' < l) then Some (l',l1,l2) else p in
  let internals_are_ok iso =
    IntMap.fold
      (fun k a out->
       out &&
	 let a' = IntMap.find iso.(k) cc2.internals in
	 Tools.array_fold_left2i (fun _ b x y -> b && x = y) true a a')
      cc1.internals true in
  let rec admissible_mapping iso = function
    | [] -> if internals_are_ok iso then [iso] else []
    | (x,y) :: t ->
       let cand = iso.(x) in
       if cand <> -1 then
       if cand = y then admissible_mapping iso t else []
       else
	 let () = iso.(x) <- y in
	 let n_x = IntMap.find x cc1.links in
	 let n_y = IntMap.find y cc2.links in
	 try
	   let remains =
	     Tools.array_fold_left2i
	       (fun _ out a b -> match a,b with
			       | ((UnSpec, UnSpec) | (Free, Free)) -> out
			       | Link (a,i), Link (b,j)
				    when i = j -> (a,b)::out
			       | (UnSpec | Free | Link _), _ ->
				  raise Not_found) t n_x n_y in
	   admissible_mapping iso remains
	 with Not_found -> []
  in
  if cc1 == cc2 then [Array.init max_id (fun x -> x)] else
    match Tools.array_fold_left2i always_equal_min_but_not_null (Some (0,[],[]))
				  cc1.nodes_by_type cc2.nodes_by_type with
    | None -> []
    | Some (_,l1,l2) ->
       match l1 with
       | [] -> let empty_inj = Array.make max_id (-1) in [empty_inj]
       | h :: _ ->
	  let rec find_admissible = function
	    | [] -> []
	    | x ::  t ->
	       let empty_inj = Array.make max_id (-1) in
	       match admissible_mapping empty_inj [(h,x)] with
	       | [] -> find_admissible t
	       | _ :: _ as l -> l in
	  find_admissible l2

let find_ty cc id =
  let rec aux i =
    assert (i >= 0);
    if List.mem id cc.nodes_by_type.(i) then i else aux (pred i)
  in aux (Array.length cc.nodes_by_type - 1)

let print with_id sigs f cc =
  let print_intf (_,_,ag_i as ag) link_ids internals neigh =
    snd
      (Tools.array_fold_lefti
	 (fun p (not_empty,(free,link_ids as out)) el ->
	  if p = 0 then (not_empty, out)
	  else
	    let () =
	      if internals.(p) >= 0
	      then Format.fprintf f "%t%a"
				  (if not_empty then Pp.comma else Pp.empty)
				  (print_internal ~sigs ag p) internals.(p)
	      else
		if  el <> UnSpec then
		  Format.fprintf f "%t%a"
				 (if not_empty then Pp.comma else Pp.empty)
				 (print_site ~sigs ag) p in
	    match el with
	    | UnSpec ->
	       if internals.(p) >= 0
	       then let () = Format.fprintf f "?" in (true,out)
	       else (not_empty,out)
	    | Free -> true,out
	    | Link (dst_a,dst_p) ->
	       let i,out' =
		 try (Int2Map.find (dst_a,dst_p) link_ids, out)
		 with Not_found ->
		   (free,(succ free, Int2Map.add (ag_i,p) free link_ids)) in
	       let () = Format.fprintf f "!%i" i in
	       true,out') (false,link_ids) neigh) in
  let () = Format.pp_open_box f 2 in
  let () = if with_id then Format.fprintf f "/*cc%i*/@ " cc.id in
  let (_,_) =
    IntMap.fold
      (fun x el (not_empty,link_ids) ->
       let ag_x = (cc.id,find_ty cc x,x) in
       let () =
	 Format.fprintf
	   f "%t@[<h>%a("
	   (if not_empty then Pp.comma else Pp.empty)
	   (print_node ~sigs) ag_x in
       let out = print_intf ag_x link_ids (IntMap.find x cc.internals) el in
       let () = Format.fprintf f ")@]" in
       true,out) cc.links (false,(1,Int2Map.empty)) in
  Format.pp_close_box f ()

let print_dot sigs f cc =
  let pp_one_node x i f = function
    | UnSpec -> ()
    | Free ->
       let n = (cc.id,find_ty cc x,x) in
       if i <> 0 then
	 let () = Format.fprintf
		    f "@[%a@ [label=\"%t\",@ height=\".1\",@ width=\".1\""
		    (print_site ?sigs:None n) i print_bot in
	 let () =
	   Format.fprintf f ",@ margin=\".05,.02\",@ fontsize=\"11\"];@]@," in
	 let () = Format.fprintf
		    f "@[<b>%a ->@ %a@ @[[headlabel=\"%a\",@ weight=\"25\""
		    (print_site ?sigs:None n) i (print_node ?sigs:None) n
		    (print_site ~sigs n) i in
	 Format.fprintf f",@ arrowhead=\"odot\",@ minlen=\".1\"]@];@]@,"
       else Format.fprintf f "@[%a [label=\"%a\"]@];@,"
			   (print_node ?sigs:None) n (print_node ~sigs) n
    | Link (y,j) ->
       let n = (cc.id,find_ty cc x,x) in
       let n' = (cc.id,find_ty cc y,y) in
       if x<y || (x=y && i<j) then
	 let () = Format.fprintf
		    f
		    "@[<b>%a ->@ %a@ @[[taillabel=\"%a\",@ headlabel=\"%a\""
		    (print_node ?sigs:None) n (print_node ?sigs:None) n'
		    (print_site ~sigs n) i (print_site ~sigs n') j in
	 Format.fprintf
	   f ",@ arrowhead=\"odot\",@ arrowtail=\"odot\",@ dir=\"both\"]@];@]@,"
  in
  let pp_one_internal x i f k =
    let n = (cc.id,find_ty cc x,x) in
    if k >= 0 then
      let () = Format.fprintf
		 f "@[%ai@ [label=\"%a\",@ height=\".1\",@ width=\".1\""
		 (print_site ?sigs:None n) i (print_internal ~sigs n i) k in
      let () =
	Format.fprintf f ",@ margin=\".05,.02\",@ fontsize=\"11\"];@]@," in
      let () = Format.fprintf
		 f "@[<b>%ai ->@ %a@ @[[headlabel=\"%a\",@ weight=25"
		 (print_site ?sigs:None n) i (print_node ?sigs:None) n
		 (print_site ~sigs n) i in
      Format.fprintf f ",@ arrowhead=\"odot\",@ minlen=\".1\"]@];@]@," in
  let pp_slot pp_el f (x,a) =
    Pp.array (fun _ -> ()) (pp_el x) f a in
  Format.fprintf
    f "@[<v>subgraph %i {@,%a%a}@]" cc.id
    (Pp.set ~trailing:(fun f -> Format.pp_print_cut f ())
	    IntMap.bindings (fun f -> Format.pp_print_cut f ())
	    (pp_slot pp_one_node)) cc.links
    (Pp.set ~trailing:(fun f -> Format.pp_print_cut f ())
	    IntMap.bindings (fun f -> Format.pp_print_cut f ())
	    (pp_slot pp_one_internal)) cc.internals

let print_sons_dot cc_id f sons =
  let pp_edge f ((n,p),e) =
    match e with
    | ToNode (n',p') ->
       Format.fprintf f "(%i,%i) -> (%i,%i)" n p n' p'
    | ToNew (n',p') ->
       Format.fprintf f "(%i,%i) -> (%i,%i) + (%i,0)" n p n' p' n'
    | ToNothing ->
       Format.fprintf f "(%i,%i) -> %t" n p print_bot
    | ToInternal i ->
       Format.fprintf f "(%i,%i)~%i" n p i in
  Pp.list Pp.space ~trailing:Pp.space
	  (fun f son -> Format.fprintf f "@[cc%i -> cc%i [label=\"%a\"];@]"
				       cc_id son.dst pp_edge son.extra_edge)
	  f sons

let print_point_dot sigs f (id,point) =
  let style = if point.is_obs then "box" else "circle" in
  Format.fprintf f "@[cc%i [label=\"%a\", shape=\"%s\"];@]@,%a"
		 point.cc.id (print false sigs) point.cc
		 style (print_sons_dot id) point.sons

module Env : sig
  type t

  val fresh : Signature.s -> int list array -> int -> point IntMap.t -> t
  val empty : Signature.s -> t
  val sigs : t -> Signature.s
  val find : t -> cc -> (int * int array * point) option
  val get : t -> int -> point
  val check_vitality : t -> unit
  val cc_map : t -> cc IntMap.t
  val add_point : int -> point -> t -> t
  val to_work : t -> work
  val fresh_id : t -> int
  val nb_ag : t -> int
  val print : Format.formatter -> t -> unit
  val print_dot : Format.formatter -> t -> unit
end = struct
  type t = {
    sig_decl: Signature.s;
    id_by_type: int list array;
    nb_id: int;
    domain: point IntMap.t;
    mutable used_by_a_begin_new: bool;
  }

let fresh sigs id_by_type nb_id domain =
  {
    sig_decl = sigs;
    id_by_type = id_by_type;
    nb_id = nb_id;
    domain = domain;
    used_by_a_begin_new = false;
  }

let empty sigs =
  let nbt = Array.make (Signature.size sigs) [] in
  let nbt' = Array.make (Signature.size sigs) [] in
  let empty_cc = {id = 0; nodes_by_type = nbt;
		  links = IntMap.empty; internals = IntMap.empty;} in
  let empty_point =
    {cc = empty_cc; is_obs = false; fathers = []; sons = [];} in
  fresh sigs nbt' 1 (IntMap.add 0 empty_point IntMap.empty)

let check_vitality env = assert (env.used_by_a_begin_new = false)

let cc_map env = IntMap.fold (fun i x out ->
			      if x.is_obs then IntMap.add i x.cc out else out)
			     env.domain IntMap.empty
let print f env =
  Format.fprintf
    f "@[<v>%a@]"
    (Pp.set ~trailing:Pp.space IntMap.bindings Pp.space
	    (fun f (_,p) ->
	     Format.fprintf f "@[<h>(%a) -> %a -> (%a)@]"
			    (Pp.list Pp.space Format.pp_print_int) p.fathers
			    (print true env.sig_decl) p.cc
			    (Pp.list Pp.space
				     (fun f s -> Format.pp_print_int f s.dst))
			    p.sons))
    env.domain

let add_point id el env =
  {
    sig_decl = env.sig_decl;
    id_by_type = env.id_by_type;
    nb_id = env.nb_id;
    domain = IntMap.add id el env.domain;
    used_by_a_begin_new = false;
  }

let fresh_id env =
  if IntMap.is_empty env.domain then 0
  else succ (IntMap.max_key env.domain)

let sigs env = env.sig_decl

let to_work env =
  let () = check_vitality env in
  let () = env.used_by_a_begin_new <- true in
  {
    sigs = env.sig_decl;
    cc_env = env.domain;
    reserved_id = env.id_by_type;
    used_id = Array.make (Array.length env.id_by_type) [];
    free_id = env.nb_id;
    cc_id = fresh_id env;
    cc_links = IntMap.empty;
    cc_internals = IntMap.empty;
    dangling = (0,0,0);
  }

let find env cc =
  IntMap.fold (fun id point ->
	       function
	       | Some _ as o -> o
	       | None ->
		  match equal env.nb_id point.cc cc with
		  | [] -> None
		  | inj :: _ -> Some (id,inj,point))
	      env.domain None

let get env cc_id = IntMap.find cc_id env.domain

let nb_ag env = env.nb_id

let print_dot f env =
  let () = Format.fprintf f "@[<v>strict digraph G {@," in
  let () =
    Pp.set ~trailing:Pp.space IntMap.bindings Pp.space
	   (print_point_dot (sigs env)) f env.domain in
  Format.fprintf f "}@]@."
end

let propagate_add_obs obs_id env cc_id =
  let rec aux son_id domain cc_id =
    let cc = Env.get domain cc_id in
    let sons' =
      Tools.list_smart_map
	(fun s -> if s.dst = son_id && not (List.mem obs_id s.above_obs)
		  then {s with above_obs = obs_id::s.above_obs}
		  else s) cc.sons in
    if sons' == cc.sons then domain
    else
      let env' =
	Env.add_point cc_id {cc with sons = sons'} domain in
      List.fold_left (aux cc_id) env' cc.fathers in
  List.fold_left (aux cc_id) env (Env.get env cc_id).fathers

exception Found

let update_cc cc_id cc ag_id links internals =
  { id = cc_id;
    nodes_by_type = cc.nodes_by_type;
    internals = IntMap.add ag_id internals cc.internals;
    links = IntMap.add ag_id links cc.links;}

let remove_ag_cc cc_id cc ag_id =
    { id = cc_id;
      nodes_by_type =
	Array.map
	  (Tools.list_smart_filter (fun x -> x <> ag_id))
	  cc.nodes_by_type;
      links = IntMap.remove ag_id cc.links;
      internals = IntMap.remove ag_id cc.internals;}

let compute_cycle_edges cc =
  let rec aux don acc path ag_id =
    Tools.array_fold_lefti
      (fun i (don,acc as out) ->
	     function
	     | UnSpec | Free -> out
	     | Link (n',i') ->
		if List.mem n' don then out
		else
		  let edge = ((ag_id,i),ToNode(n',i')) in
		  if ag_id = n' then (don, edge::acc)
		  else
		    let rec extract_cycle acc' = function
		      | ((n,i),_ as e) :: t ->
			 if n' = n then
			   if i' = i then out
			   else (don,edge::e::acc')
			 else extract_cycle (e::acc') t
		      | [] ->
			 let (don',acc') = aux don acc (edge::path) n' in
			 (n'::don',acc') in
		    extract_cycle acc path)
      (don,acc) (IntMap.find ag_id cc.links) in
  let rec element i t =
    if i = Array.length t then [] else
      match t.(i) with
      | [] -> element (succ i) t
      | h :: _ -> snd (aux [] [] [] h) in
  element 0 cc.nodes_by_type

let remove_cycle_edges free_id cc =
  let rec aux (free_id,acc as out) = function
    | ((n,i),ToNode(n',i') as e) :: q ->
       let links = IntMap.find n cc.links in
       let int = IntMap.find n cc.internals in
       let links' = Array.copy links in
       let () = links'.(i) <- UnSpec in
       let cc_tmp = update_cc free_id cc n links' int in
       let links_dst = IntMap.find n' cc_tmp.links in
       let int_dst = IntMap.find n' cc_tmp.internals in
       let links_dst' = Array.copy links_dst in
       let () = links_dst'.(i') <- UnSpec in
       let cc' = update_cc free_id cc_tmp n' links_dst' int_dst in
       aux (succ free_id,(cc',e)::acc) q
    | l -> assert (l = []); out in
  aux (free_id,[]) (compute_cycle_edges cc)

let compute_father_candidates free_id cc =
  let agent_is_removable lp links internals =
    try
      let () = Array.iter (fun el -> if el >= 0 then raise Found) internals in
      let () =
	Array.iteri
	  (fun i el -> if i>0 && i<>lp && el<>UnSpec then raise Found) links in
      true
    with Found -> false in
  let remove_one_internal acc ag_id links internals =
    Tools.array_fold_lefti
      (fun i (f_id, out as acc) el ->
       if el >= 0 then
	 let int' = Array.copy internals in
	 let () = int'.(i) <- -1 in
	 (succ f_id,
	  (update_cc f_id cc ag_id links int',((ag_id,i),ToInternal el))::out)
       else acc)
      acc internals in
  let remove_one_frontier acc ag_id links internals =
    Tools.array_fold_lefti
      (fun i (f_id,out as acc) ->
       function
       | UnSpec -> acc
       | Free ->
	  if i = 0 then acc else
	    let links' = Array.copy links in
	    let () = links'.(i) <- UnSpec in
	    (succ f_id, (update_cc f_id cc ag_id links' internals,
			 ((ag_id,i),ToNothing))::out)
       | Link (n',i') ->
	  if not (agent_is_removable i links internals) then acc else
	    let links_dst = IntMap.find n' cc.links in
	    let int_dst = IntMap.find n' cc.internals in
	    let links_dst' = Array.copy links_dst in
	    let () = links_dst'.(i') <- UnSpec in
	    let cc' = update_cc f_id (remove_ag_cc f_id cc ag_id)
				n' links_dst' int_dst in
	    succ f_id,
	    (cc',((n',i'),ToNew (ag_id,i)))::out)
      (remove_one_internal acc ag_id links internals) links in
  let remove_or_remove_one (f_id,out as acc) ag_id links internals =
    if agent_is_removable 0 links internals then
      succ f_id,
      (remove_ag_cc f_id cc ag_id,((ag_id,0),ToNothing)) :: out
    else remove_one_frontier acc ag_id links internals in
  IntMap.fold (fun i links acc ->
	       remove_or_remove_one acc i links (IntMap.find i cc.internals))
	      cc.links (remove_cycle_edges free_id cc)

let rec complete_domain_with obs_id dst env free_id cc edge =
  let new_son inj =
    { dst = dst; extra_edge = edge;
      inj = inj; above_obs = [obs_id];} in
  let known_cc = Env.find env cc in
  match known_cc with
  | Some (cc_id, inj, point') ->
     let point'' = {point' with sons = new_son inj :: point'.sons} in
     (free_id,propagate_add_obs obs_id (Env.add_point cc_id point'' env) cc_id)
     , cc_id
  | None ->
     let son = new_son (Array.init (Env.nb_ag env) (fun x -> x)) in
     add_new_point obs_id env free_id [son] cc
and add_new_point obs_id env free_id sons cc =
  let (free_id',cand) = compute_father_candidates free_id cc in
  let (free_id'',env'),fathers =
    Tools.list_fold_right_map
      (fun (free_id'',env') (cc', edge) ->
		      complete_domain_with obs_id cc.id env' free_id'' cc' edge)
	   (free_id',env) cand in
       ((free_id'',
	 Env.add_point
	   cc.id
	   {cc = cc; is_obs = cc.id = obs_id; sons=sons; fathers = fathers;}
	   env')
       ,cc.id)

let add_domain env cc =
  let known_cc = Env.find env cc in
  match known_cc with
  | Some (id,_,point) ->
     (if point.is_obs then env
      else propagate_add_obs id env id),point.cc
  | None ->
     let (_,env'),_ = add_new_point cc.id env (succ cc.id) [] cc in
     (env',cc)

(** Operation to create cc *)
let check_dangling wk =
  if wk.dangling <> (0,0,0) then
    raise (dangling_node ~sigs:wk.sigs wk.dangling)
let check_node_adequacy ~pos wk cc_id =
  if wk.cc_id <> cc_id then
    raise (
	ExceptionDefn.Malformed_Decl
	  (Format.asprintf
		"A node from a different connected component has been used."
	  ,pos))

let begin_new env = Env.to_work env

let finish_new wk =
  let () = check_dangling wk in
  (** rebuild env **)
  let () =
    Tools.iteri
      (fun i ->
       wk.reserved_id.(i) <- List.rev_append wk.used_id.(i) wk.reserved_id.(i))
      (Array.length wk.used_id) in
  let cc_candidate =
    { id = wk.cc_id; nodes_by_type = wk.used_id;
      links = wk.cc_links; internals = wk.cc_internals; } in
  let env = Env.fresh wk.sigs wk.reserved_id wk.free_id wk.cc_env in
  add_domain env cc_candidate


let new_link wk ((cc1,_,x as n1),i) ((cc2,_,y as n2),j) =
  let pos = (Lexing.dummy_pos,Lexing.dummy_pos) in
  let () = check_node_adequacy ~pos wk cc1 in
  let () = check_node_adequacy ~pos wk cc2 in
  let x_n = IntMap.find x wk.cc_links in
  let y_n = IntMap.find y wk.cc_links in
  if x_n.(i) <> UnSpec then
    raise (already_specified ~sigs:wk.sigs n1 i)
  else if y_n.(j) <> UnSpec then
    raise (already_specified ~sigs:wk.sigs n2 j)
  else
    let () = x_n.(i) <- Link (y,j) in
    let () = y_n.(j) <- Link (x,i) in
    if wk.dangling = n1 || wk.dangling = n2
    then { wk with dangling = (0,0,0) }
    else wk

let new_free wk ((cc,_,x as n),i) =
  let () = check_node_adequacy ~pos:(Lexing.dummy_pos,Lexing.dummy_pos) wk cc in
  let x_n = IntMap.find x wk.cc_links in
  if x_n.(i) <> UnSpec then
    raise (already_specified ~sigs:wk.sigs n i)
  else
    let () = x_n.(i) <- Free in
    wk

let new_internal_state wk ((cc,_,x as n), i) va =
  let () = check_node_adequacy ~pos:(Lexing.dummy_pos,Lexing.dummy_pos) wk cc in
  let x_n = IntMap.find x wk.cc_internals in
  if x_n.(i) >= 0 then
    raise (already_specified ~sigs:wk.sigs n i)
  else
    let () = x_n.(i) <- va in
    wk

let new_node wk type_id =
  let () = check_dangling wk in
  let arity = Signature.arity wk.sigs type_id in
  match wk.reserved_id.(type_id) with
  | h::t ->
     let () = wk.used_id.(type_id) <- h :: wk.used_id.(type_id) in
     let () = wk.reserved_id.(type_id) <- t in
     let node = (wk.cc_id,type_id,h) in
     (node,
      new_free
	{ wk with
	  dangling = if IntMap.is_empty wk.cc_links then (0,0,0) else node;
	  cc_links = IntMap.add h (Array.make arity UnSpec) wk.cc_links;
	  cc_internals = IntMap.add h (Array.make arity (-1)) wk.cc_internals;
	} (node,0))
  | [] ->
     let () = wk.used_id.(type_id) <- wk.free_id :: wk.used_id.(type_id) in
     let node = (wk.cc_id, type_id, wk.free_id) in
     (node,
      new_free
	{ wk with
	  free_id = succ wk.free_id;
	  dangling = if IntMap.is_empty wk.cc_links then (0,0,0) else node;
	  cc_links =
	    IntMap.add wk.free_id (Array.make arity UnSpec) wk.cc_links;
	  cc_internals =
	    IntMap.add wk.free_id (Array.make arity (-1)) wk.cc_internals;
	} (node,0))

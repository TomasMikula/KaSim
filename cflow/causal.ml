open Mods

type event_kind = OBS of int | RULE of int | INIT | PERT of int

type quark_lists = {
  site_tested : (int * int) list;
  site_modified : (int * int) list;
  internal_state_tested : (int * int) list;
  internal_state_modified : (int * int) list;
}

let atom_tested = 1
let atom_modified = 2
let atom_testedmodified = 3
type atom =
    {
      causal_impact : int ; (*(1) tested (2) modified, (3) tested + modified*)
      eid:int ; (*event identifier*)
      kind:event_kind ;
(*      observation: string list*)
    }

type attribute = atom list (*vertical sequence of atoms*)
type grid =
    {
      flow: (int*int*int,attribute) Hashtbl.t ;
      (*(n_i,s_i,q_i) -> att_i with n_i: node_id, s_i: site_id, q_i:
      link (1) or internal state (0) *)
      pid_to_init: (int*int*int,int) Hashtbl.t ;
      obs: int list ;
      weak_list: int list ;
      init_tbl: (int,Mods.IntSet.t) Hashtbl.t;(*decreasing*)
      init_to_eidmax: (int,int) Hashtbl.t;
    }
type config =
    {
      events: atom IntMap.t ;
      prec_1: IntSet.t IntMap.t ;
      conflict : IntSet.t IntMap.t ;
      top : IntSet.t}
type enriched_grid =
    {
      config:config;
      ids:(int * int * int) list ;
      depth:int;
      prec_star: int list array ; (*decreasing*)
      depth_of_event: int Mods.IntMap.t ;
      size:int;
    }

let empty_config =
  {events=IntMap.empty ;
   conflict = IntMap.empty ;
   prec_1 = IntMap.empty ;
   top = IntSet.empty}

let debug_print_event_kind f = function
  | OBS i -> Format.fprintf f "OBS(%i)" i
  | RULE i -> Format.fprintf f "RULE(%i)" i
  | INIT -> Format.fprintf f "INIT"
  | PERT i -> Format.fprintf f "PERT(%i)" i

let debug_print_causal f i =
  Format.pp_print_string
    f (if i = atom_tested then "tested"
       else if i = atom_modified then "modified"
       else if i = atom_tested lor atom_modified then "tested&modified"
       else "CAUSAL IMPACT UNDEFINED")

let debug_print_atom f a =
  Format.fprintf f "{#%i: %a %a}" a.eid debug_print_causal a.causal_impact
		 debug_print_event_kind a.kind

let debug_print_grid f g =
  let () =
    Format.fprintf f "@[<v>Flow:@," in
  let () = Hashtbl.iter
	     (fun (node_id,site_id,q) l ->
	      Format.fprintf
		f "@[<2>%i.%i%s:@,%a@]@," node_id site_id
		(if q = 0 then "~" else if q = 1 then "" else "UNDEFINED")
		(Pp.list Pp.space debug_print_atom) l)
	     g.flow in
  Format.fprintf f "@]@."

let empty_grid () =
  {
    flow = Hashtbl.create !Parameter.defaultExtArraySize ;
    pid_to_init = Hashtbl.create !Parameter.defaultExtArraySize ;
    obs = [] ;
    weak_list = [] ;
    init_tbl = Hashtbl.create !Parameter.defaultExtArraySize ;
    init_to_eidmax = Hashtbl.create !Parameter.defaultExtArraySize
  }

let build_subs l =
  snd (List.fold_left
	 (fun (n,map) a -> (succ n,IntMap.add a n map)) (1,IntMap.empty) l)

let submap subs l m default =
  List.fold_left
    (fun m' a ->
     let new_a = IntMap.find a subs in
     IntMap.add new_a (
		  try IntMap.find a m
		  with Not_found ->
		       match default with None -> raise Not_found | Some a -> a
		) m')
    IntMap.empty l

let add_init_pid eid pid grid =
  let eid_init = Hashtbl.find grid.pid_to_init pid in
  let old =
    try Hashtbl.find grid.init_tbl eid
    with Not_found -> Mods.IntSet.empty
  in
  let () = Hashtbl.replace grid.init_tbl eid (Mods.IntSet.add eid_init old) in
  let () = Hashtbl.replace grid.init_to_eidmax eid_init eid in
  grid

let subset subs l s =
  List.fold_left
    (fun s' a ->
     if IntSet.mem a s then IntSet.add (IntMap.find a subs) s' else s')
    IntSet.empty l

let subconfig_with_subs subs config l =
  {events = submap subs l config.events None ;
   prec_1 = submap subs l config.prec_1 (Some IntSet.empty);
   conflict = submap subs l config.conflict (Some IntSet.empty);
   top = subset subs l config.top}
let subenriched_grid_with_subs subs  grid l =
  let depth_of_event = submap subs  l grid.depth_of_event (Some 0) in
  let depth = IntMap.fold (fun _ -> max) depth_of_event 0 in
  {
    ids = grid.ids;
    prec_star = grid.prec_star;
    config = subconfig_with_subs subs  grid.config l ;
    depth_of_event = depth_of_event ;
    depth = depth ;
    size = List.length l ;
  }

let subconfig config l = subconfig_with_subs (build_subs l) config l
let subenriched_grid grid l = subenriched_grid_with_subs (build_subs l) grid l

let add_obs_eid eid grid = {grid with obs = eid::(grid.obs)}

let grid_find (node_id,site_id,quark) grid =
  Hashtbl.find grid.flow (node_id,site_id,quark)

let is_empty_grid grid = (Hashtbl.length grid.flow = 0)

let grid_add quark eid (attribute:attribute) grid =
  let () =
    try
      let _ = Hashtbl.find grid.flow quark in ()
    with _ -> Hashtbl.add grid.pid_to_init quark eid
  in
  Hashtbl.replace grid.flow quark attribute ;
  grid

let last_event attribute =
  match attribute with
  | [] -> None
  | a::_ -> (Some a.eid)

(*adds atom a to attribute att.
 Collapses last atom if if bears the same id as a --in the case of a non atomic action*)
let push (a:atom) (att:atom list) =
  match att with
  | [] -> [a]
  | a'::att' ->
     if a'.eid = a.eid then
       let () = assert (a'.kind = a.kind) in
       { a' with causal_impact = a.causal_impact lor a'.causal_impact }::att'
     else a::att

(**side_effect Int2Set.t: pairs (agents,ports) that have been freed as a side effect --via a DEL or a FREE action*)
(*NB no internal state modif as side effect*)
let store_is_weak is_weak eid grid =
  if is_weak then {grid with weak_list = eid::(grid.weak_list)} else grid

(*let impact is_link c =
  if is_link then
    if Primitives.Causality.is_link_modif c then
      if Primitives.Causality.is_link_tested c then 3 else 2
    else 1
  else (*internal state*)
    if Primitives.Causality.is_internal_modif c then
      if Primitives.Causality.is_internal_tested c then 3 else 2
    else 1
 *)
let add ((node_id,_),site_id) is_link va grid event_number kind =
  let q = if is_link then 1 else 0 in
  let att =
    try grid_find (node_id,site_id,q) grid
    with Not_found -> [] in
  let att =
    push {causal_impact = va ; eid = event_number ;
	  kind = kind (*; observation = obs*)} att in
  let grid = grid_add (node_id,site_id,q) event_number att grid in
  add_init_pid event_number (node_id,site_id,q) grid

let add_actions env grid event_number kind actions =
  let rec aux grid = function
    | [] -> grid
    | Instantiation.Mod_internal (site,_) :: q ->
       aux (add site false atom_modified grid event_number kind) q
    | (Instantiation.Bind (site1,site2)
      | Instantiation.Bind_to (site1,site2)) :: q ->
       let grid' = add site2 true atom_modified grid event_number kind in
       aux (add site1 true atom_modified grid' event_number kind) q
    | Instantiation.Free site :: q ->
       aux (add site true atom_modified grid event_number kind) q
    | (Instantiation.Create ((_,na as ag),_)
      | Instantiation.Remove (_,na as ag)) :: q ->
       let sigs = Environment.signatures env in
       let ag_intf = Signature.get sigs na in
       let grid =
	 Signature.fold
	   (fun site _ grid ->
	    let grid' =
	      match Signature.default_internal_state na site sigs with
	      | None -> grid
	      | Some _ -> add (ag,site) false atom_modified grid event_number kind in
	    add (ag,site) true 1 grid' event_number kind)
	   ag_intf grid in
       aux grid q
  in aux grid actions

let add_tests grid event_number kind tests =
  let rec aux grid = function
    | [] -> grid
    | Instantiation.Is_Here _ :: q -> aux grid q
    | Instantiation.Has_Internal (site,_) :: q ->
       aux (add site false atom_tested grid event_number kind) q
    | (Instantiation.Is_Free site
      | Instantiation.Is_Bound site
      | Instantiation.Has_Binding_type (site,_)) :: q ->
       aux (add site true atom_tested grid event_number kind) q
    | Instantiation.Is_Bound_to (site1,site2) :: q ->
       let grid' = add site2 true atom_tested grid event_number kind in
       aux (add site1 true atom_tested grid' event_number kind) q
  in aux grid tests

let record (kind,(tests,(actions,_,side_effects)))
	   is_weak event_number env grid =
  let grid = store_is_weak is_weak event_number grid in
  let grid = add_tests grid event_number kind tests in
  let grid = add_actions env grid event_number kind actions in
  List.fold_left
    (fun grid site -> add site true atom_modified grid event_number kind) grid side_effects

let record_obs (kind,tests,_) side_effects is_weak event_number grid =
  let grid = add_obs_eid event_number grid in
  let grid = store_is_weak is_weak event_number grid in
  let grid = add_tests grid event_number kind tests in
  List.fold_left
    (fun grid site -> add site true atom_modified grid event_number kind) grid side_effects

let record_init actions is_weak event_number env grid =
  (* if !Parameter.showIntroEvents then *)
  (*adding tests*)
  let grid = store_is_weak is_weak event_number grid in
  add_actions env grid event_number INIT actions

let add_pred eid atom config =
  let events = IntMap.add atom.eid atom config.events in
  let pred_set =
    try IntMap.find eid config.prec_1 with Not_found -> IntSet.empty in
  let prec_1 = IntMap.add eid (IntSet.add atom.eid pred_set) config.prec_1 in
  {config with prec_1 = prec_1 ; events = events}

let add_conflict eid atom config =
  let events = IntMap.add atom.eid atom config.events in
  let cflct_set =
    try IntMap.find eid config.conflict with Not_found -> IntSet.empty in
  let cflct = IntMap.add eid (IntSet.add atom.eid cflct_set) config.conflict in
  {config with conflict = cflct ; events = events }

let rec parse_attribute last_modif last_tested attribute config =
  match attribute with
  | [] -> config
  | atom::att ->
     let events = IntMap.add atom.eid atom config.events in
     let prec_1 =
       let preds = try IntMap.find atom.eid config.prec_1
		   with Not_found -> IntSet.empty in
       IntMap.add atom.eid preds config.prec_1 in
     let config = {config with events =  events ; prec_1 = prec_1} in
     (*atom has a modification*)
     if (atom.causal_impact = atom_tested) || (atom.causal_impact = 3) then
       let config =
	 List.fold_left (fun config pred_id -> add_pred pred_id atom config)
			config last_tested in
       let tested =
	 if (atom.causal_impact = atom_tested)
	    ||(atom.causal_impact = atom_tested lor atom_modified)
	 then [atom.eid] else [] in
       parse_attribute (Some atom.eid) tested att config
     else
       (* atom is a pure test*)
       let config =
	 match last_modif with
	 | None -> config
	 | Some eid ->
	    add_conflict eid atom config (*adding conflict with last modification*) 
       in
       parse_attribute last_modif (atom.eid::last_tested) att config

let cut attribute_ids grid =
  let rec build_config attribute_ids cfg =
    match attribute_ids with
    | [] -> cfg
    | (node_i,site_i,type_i)::tl ->
       let attribute =
	 try grid_find (node_i,site_i,type_i) grid
	 with Not_found -> invalid_arg "Causal.cut" in
       let cfg =
	 match attribute with
	 | [] -> cfg
	 | atom::att ->
	    let events = IntMap.add atom.eid atom cfg.events in
	    let prec_1 =
	      let preds = try IntMap.find atom.eid cfg.prec_1
			  with Not_found -> IntSet.empty in
	      IntMap.add atom.eid preds cfg.prec_1 in
	    let top = IntSet.add atom.eid cfg.top in
	    let tested =
	      if (atom.causal_impact = atom_tested) || (atom.causal_impact = 3)
	      then [atom.eid] else [] in
	    let modif =
	      if (atom.causal_impact = atom_modified) || (atom.causal_impact = 3)
	      then Some atom.eid else None in
	    parse_attribute
	      modif tested att
	      {cfg with prec_1 = prec_1 ; events = events ; top = top}
       in build_config tl cfg
  in
  build_config attribute_ids empty_config

let pp_atom f atom =
  let imp_str = match atom.causal_impact with
      1 -> "o" | 2 -> "x" | 3 -> "%"
      | _ -> invalid_arg "Causal.string_of_atom" in
  Format.fprintf f "%s_%d" imp_str atom.eid

let dump grid fic =
  let d_chan = open_out ((Filename.chop_extension fic)^".txt") in
  let d = Format.formatter_of_out_channel d_chan in
  let () = Format.pp_open_vbox d 0 in
  Hashtbl.fold
    (fun (n_id,s_id,q) att _ ->
     Format.fprintf d "#%i.%i%c:%a@," n_id s_id (if q=0 then '~' else '!')
		    (Pp.list Pp.empty pp_atom) att
    ) grid.flow () ;
  let () = Format.fprintf d "@]@." in
  close_out d_chan

let label ?env = function
  | OBS mix_id -> Format.asprintf "%a" (Environment.print_alg ?env) mix_id
  | PERT p_id -> ""
  | RULE r_id -> Format.asprintf "%a" (Environment.print_rule ?env) r_id
  | INIT -> "initial introduction"

let ids_of_grid grid = Hashtbl.fold (fun key _ l -> key::l) grid.flow []
let config_of_grid = cut


(*let prec_star_of_config_old  config = 
  let rec prec_closure config todo already_done closure =
    if IntSet.is_empty todo then closure
    else
      let eid = IntSet.choose todo in
      let todo' = IntSet.remove eid todo in
      if IntSet.mem eid already_done 
      then 
        prec_closure config todo' already_done closure 
      else 
        let prec = try IntMap.find eid config.prec_1 with Not_found -> IntSet.empty
        in
      prec_closure config (IntSet.union todo' prec) (IntSet.add eid already_done) (IntSet.union prec closure)
  in
  IntMap.fold 
    (fun eid kind prec_star -> 
      let set = prec_closure config (IntSet.singleton eid) IntSet.empty IntSet.empty
      in
      IntMap.add eid set prec_star
    ) config.events IntMap.empty *)

let prec_star_of_config err_fmt config_closure config to_keep init_to_eidmax
			weak_events init =
  let a =
    Graph_closure.closure err_fmt config_closure config.prec_1 to_keep
			  init_to_eidmax weak_events init in
  Graph_closure.A.map fst a

let depth_and_size_of_event config =
  IntMap.fold
    (fun eid prec_eids (emap,size,depth) ->
      let d =
	IntSet.fold
	  (fun eid' d ->
	   let d' = try IntMap.find eid' emap with Not_found -> 0 in
	   max (d'+1) d
	  ) prec_eids 0
      in
      IntMap.add eid d emap,size+1,d
    ) config.prec_1 (IntMap.empty,0,0)

let enrich_grid err_fmt config_closure grid =
  let keep_l =
    List.fold_left (fun a b -> IntSet.add b a) IntSet.empty grid.obs in
  let to_keep i = IntSet.mem i keep_l in
  let ids = ids_of_grid grid  in
  let config = config_of_grid ids grid in
  let max_key = List.fold_left max 0 grid.weak_list  in
  let tbl = Graph_closure.A.make (max_key+1) false in
  let () =
    List.iter (fun i -> Graph_closure.A.set tbl i true) grid.weak_list in
  let weak_fun i = try Graph_closure.A.get tbl i with _ -> false in
  let init_fun i =
    try
      List.rev (Mods.IntSet.elements (Mods.IntSet.remove
					i (Hashtbl.find grid.init_tbl i)))
    with _ -> [] in
  let init_to_eid_max i =
    try Hashtbl.find grid.init_to_eidmax i
    with Not_found -> 0 in
  let prec_star = prec_star_of_config err_fmt config_closure config to_keep
				      init_to_eid_max weak_fun init_fun in
  let depth_of_event,size,depth = depth_and_size_of_event config in
  {
    config = config ;
    ids = ids ;
    size = size ;
    prec_star = prec_star ;
    depth = depth ;
    depth_of_event = depth_of_event
  }

let dot_of_grid profiling desc env enriched_grid =
  (*dump grid fic state env ; *)
  let t = Sys.time () in
  let config = enriched_grid.config in
  let prec_star = enriched_grid.prec_star in
  let depth_of_event = enriched_grid.depth_of_event in
  let sorted_events =
    IntMap.fold
      (fun eid d dmap ->
       let set = try IntMap.find d dmap with Not_found -> IntSet.empty in
       IntMap.add d (IntSet.add eid set) dmap
      ) depth_of_event IntMap.empty in
  let () = Kappa_files.add_out_desc desc in
  let form  = Format.formatter_of_out_channel desc in
  let _ = profiling form in
  Format.fprintf form "@[<v>digraph G{@, ranksep=.5 ;@," ;
  IntMap.iter
    (fun d eids_at_d ->
     Format.fprintf form "@[<hv>{ rank = same ; \"%d\" [shape=plaintext] ;@," d;
     IntSet.iter
       (fun eid ->
	let atom = IntMap.find eid config.events in
	if eid <> 0 then
	  match atom.kind  with
	  | RULE _  ->
	     Format.fprintf
	       form
	       "node_%d [label=\"%s\", shape=%s, style=%s, fillcolor = %s] ;@,"
	       eid (label ~env atom.kind) "invhouse" "filled" "lightblue"
          | OBS _  ->
	     Format.fprintf
	       form "node_%d [label=\"%s\", style=filled, fillcolor=red] ;@,"
	       eid (label ~env atom.kind)
        | INIT  ->
	   if !Parameter.showIntroEvents then
	     Format.fprintf
	       form
	       "node_%d [label=\"%s\", shape=%s, style=%s, fillcolor=%s] ;@,"
	       eid (label ~env atom.kind) "house" "filled" "green"
	| PERT _ -> invalid_arg "Event type not handled"
       (* List.iter (fun obs -> fprintf desc "obs_%d [label =\"%s\", style=filled, fillcolor=red] ;\n node_%d -> obs_%d [arrowhead=vee];\n" eid obs eid eid) atom.observation ;*) 
       ) eids_at_d ;
     Format.fprintf form "}@]@," ;
    ) sorted_events ;
  let cpt = ref 0 in
  while !cpt+1 < (IntMap.size sorted_events) do
    Format.fprintf form "\"%d\" -> \"%d\" [style=\"invis\"];@," !cpt (!cpt+1);
    cpt := !cpt + 1
  done ;
  IntMap.iter
    (fun eid pred_set ->
     if eid <> 0 then
       IntSet.iter
	 (fun eid' ->
	  if eid' = 0 then ()
	  else
	    if !Parameter.showIntroEvents then
	      Format.fprintf form "node_%d -> node_%d@," eid' eid
	    else
	      let atom = IntMap.find eid' config.events in
	      match atom.kind with
	      | INIT -> ()
	      | PERT _ | RULE _ | OBS _ -> Format.fprintf form "node_%d -> node_%d@," eid' eid
	 ) pred_set
    ) config.prec_1 ;
  IntMap.iter
    (fun eid cflct_set ->
     if eid <> 0 then
       let prec = try prec_star.(eid) with _ -> [] in
       let _ =
         IntSet.fold_inv
           (fun eid' prec ->
            let bool,prec =
              let rec aux prec =
                match prec with
                | []   -> true,prec
                | h::t ->
                   if h=eid' then false,t else
		     if h>eid' then aux t else true,prec
              in aux prec in
            let () =
	      if bool then
		Format.fprintf
		  form "node_%d -> node_%d [style=dotted, arrowhead = tee]@ "
		  eid eid'
            in
            prec
	   ) cflct_set prec
       in ()
    ) config.conflict ;
  Format.fprintf form "}@," ;
  Format.fprintf form "/*@, Dot generation time: %f@,*/@]@." (Sys.time () -. t);
  close_out desc

(*story_list:[(key_i,list_i)] et list_i:[(grid,_,sim_info option)...] et sim_info:{with story_id:int story_time: float ; story_event: int}*)
let pretty_print err_fmt env config_closure compression_type label story_list =
  let n = List.length story_list in
  let () =
    if compression_type = "" then
      Format.fprintf err_fmt "@.+ Pretty printing %d flow%s@."
		     n (if n>1 then "s" else "")
    else
      Format.fprintf err_fmt "@.+ Pretty printing %d %scompressed flow%s@."
		     n label (if n>1 then "s" else "")
  in
  let compression_type =
    if compression_type = "" then "none" else compression_type in
  let story_list =
    List.map (fun (x,y) -> enrich_grid err_fmt config_closure x,y) story_list in
  let _ =
    List.fold_left
      (fun cpt (enriched_config,stories) ->
       let av_t,ids,n =
	 List.fold_left
	   (fun (av_t,ids,n) info_opt ->
	    match info_opt with
	    | Some info ->
               (av_t +. info.story_time,info.story_id::ids,n+1)
	    | None -> invalid_arg "Causal.pretty_print"
	   )(0.,[],0) (List.rev stories)
       in
       let profiling desc =
	 Format.fprintf
	   desc "/* @[Compression of %d causal flows@ obtained in average at %E t.u@] */@."
	   n (av_t/.(float_of_int n)) ;
	 Format.fprintf desc "@[/* Compressed causal flows were:@ [%a] */@]@."
			(Pp.list (fun f -> Format.fprintf f ";@,")
				 Format.pp_print_int) ids
	in
	let desc = Kappa_files.fresh_cflow_filename
		     [compression_type;string_of_int cpt] "dot" in
        let () = dot_of_grid profiling desc env enriched_config in
	close_out desc;
	cpt+1
      ) 0 story_list
  in
  let desc =
    Kappa_files.fresh_cflow_filename [compression_type;"Summary"] "dat" in
  let form = Format.formatter_of_out_channel desc in
  let () = Format.fprintf form "@[<v>#id\tE\tT\t\tdepth\tsize\t@," in
  let () =
    Pp.listi Pp.empty
	    (fun cpt f (enriched_config,story) ->
	     let depth = enriched_config.depth in
	     let size = enriched_config.size in
	     List.iter
               (fun story ->
		match story with
		| None -> invalid_arg "Causal.pretty_print"
		| Some info ->
		   let time = info.story_time in
		   let event = info.story_event in
		   Format.fprintf f "%i\t%i\t%E\t%i\t%i\t@,"
				  cpt event time depth size
               ) story) form story_list in
  let () = Format.fprintf form "@]@?" in
  close_out desc

let print_stat f parameter handler enriched_grid =
  let size = Array.length enriched_grid.prec_star in
  let rec aux k n_step longest_story n_nonempty length_sum length_square_sum =
    if k>=size
    then (n_step,longest_story,n_nonempty,length_sum,length_square_sum)
    else
      let cc = List.length (Array.get enriched_grid.prec_star k) in
      aux (k+1) (n_step+1) (max longest_story cc)
        (if cc>0 then n_nonempty+1 else n_nonempty)
        (length_sum+cc) (length_square_sum+cc*cc) in
  let n_step,longest_story,n_nonempty,length_sum,length_square_sum =
    aux 0 0 0 0 0 0 in
  let () = Format.fprintf f "@[<v>@," in
  let () = Format.fprintf f  "Stats:@," in
  let () = Format.fprintf f " number of step   : %i@," n_step in
(*  let () = Format.fprintf f " number of stories: %i@," n_nonempty in *)
  let () = Format.fprintf f " longest story    : %i@," longest_story in
  let () = Format.fprintf f " average length   : %F@,"
			  (float length_sum /. float n_nonempty) in
  let () = Format.fprintf f " geometric mean   : %F@,"
			  (sqrt (float length_square_sum /. float n_nonempty)) in
  Format.fprintf f "@]@."

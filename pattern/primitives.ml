module Place =
  struct
    type t =
	Existing of Connected_component.ContentAgent.t * int
      | Fresh of int * int (* type, id *)

    let rename wk id cc inj = function
      | Existing (n, id') as x ->
	 if id <> id' then x else
	   let n' = Connected_component.ContentAgent.rename wk cc inj n in
	   if n == n' then x else Existing (n',id')
      | Fresh _ as x -> x

    let print ?sigs f = function
      | Existing (n,id) ->
	 Format.fprintf f "%a/*%i*/"
			(Connected_component.ContentAgent.print ?sigs) n id
      | Fresh (ty,i) ->
	 Format.fprintf f "%a/*%t %i*/"
			(match sigs with
			 | None -> Format.pp_print_int
			 | Some sigs -> Signature.print_agent sigs) ty Pp.nu i

    let print_site ?sigs place f site =
      match place with
      | Existing (n,_) ->
	 Connected_component.ContentAgent.print_site ?sigs n f site
      | Fresh (ty,_) ->
	 match sigs with
	 | None -> Format.pp_print_int f ty
	 | Some sigs -> Signature.print_site sigs ty f site

    let print_internal ?sigs place site f id =
      match place with
      | Existing (n,_) ->
	 Connected_component.ContentAgent.print_internal ?sigs n site f id
      | Fresh (ty,_) ->
	 match sigs with
	 | None -> Format.pp_print_int f id
	 | Some sigs ->
	    Signature.print_site_internal_state sigs ty site f (Some id)

    let get_type = function
      | Existing (n,_) -> Connected_component.ContentAgent.get_sort n
      | Fresh (i,_) -> i

    let is_site_from_fresh = function
      | (Existing _,_) -> false
      | (Fresh _, _) -> true
  end

module Transformation =
  struct
    type t =
	Freed of Place.t * int
      | Linked of (Place.t * int) * (Place.t * int)
      | Internalized of Place.t * int * int

    let rename wk id cc inj = function
      | Freed (p,s) as x ->
	 let p' = Place.rename wk id cc inj p in
	 if p == p' then x else Freed (p',s)
      | Linked ((p1,s1),(p2,s2)) as x ->
	 let p1' = Place.rename wk id cc inj p1 in
	 let p2' = Place.rename wk id cc inj p2 in
	 if p1 == p1' && p2 == p2' then x else Linked ((p1',s1),(p2',s2))
      | Internalized (p,s,i) as x ->
	 let p' = Place.rename wk id cc inj p in
	 if p == p' then x else Internalized (p',s,i)

    let print ?sigs f = function
      | Freed (p,s) ->
	 Format.fprintf
	   f "@[%a.%a = %t@]" (Place.print ?sigs) p
	   (Place.print_site ?sigs p) s Pp.bottom
      | Linked ((p1,s1),(p2,s2)) ->
	 Format.fprintf
	   f "@[%a.%a = %a.%a@]"
	   (Place.print ?sigs) p1 (Place.print_site ?sigs p1) s1
	   (Place.print ?sigs) p2 (Place.print_site ?sigs p2) s2
      | Internalized (p,s,i) ->
	 Format.fprintf
	   f "@[%a.%a =@]" (Place.print ?sigs) p
	   (Place.print_internal ?sigs p s) i
  end

module Instantiation =
  struct
    type agent_name = int
    type site_name = int
    type internal_state  = int

    type binding_type = agent_name * site_name

    type abstract = Place.t
    type concrete = int (*agent_id*) * agent_name

    type 'a site = 'a * site_name

    type 'a test =
      | Is_Here of 'a
      | Has_Internal of 'a site * internal_state
      | Is_Free of 'a site
      | Is_Bound of 'a site
      | Has_Binding_type of 'a site * binding_type
      | Is_Bound_to of 'a site * 'a site

    type 'a action =
      | Create of 'a * (site_name * internal_state option) list (* pourquoi ça *)
      | Mod_internal of 'a site * internal_state
      | Bind of 'a site * 'a site
      | Bind_to of 'a site * 'a site
      | Free of 'a site
      | Remove of 'a

    type 'a binding_state =
      | ANY
      | FREE
      | BOUND
      | BOUND_TYPE of binding_type
      | BOUND_to of 'a site

    type 'a event =
	'a test list *
	  ('a action list * ('a site * 'a binding_state) list * 'a site list)

    let concretize_binding_state f = function
      | ANY -> ANY
      | FREE -> FREE
      | BOUND -> BOUND
      | BOUND_TYPE bt -> BOUND_TYPE bt
      | BOUND_to (pl,s) -> BOUND_to ((f pl,Place.get_type pl),s)

    let concretize_test f = function
      | Is_Here pl -> Is_Here (f pl,Place.get_type pl)
      | Has_Internal ((pl,s),i) -> Has_Internal(((f pl,Place.get_type pl),s),i)
      | Is_Free (pl,s) -> Is_Free ((f pl,Place.get_type pl),s)
      | Is_Bound (pl,s) -> Is_Bound ((f pl,Place.get_type pl),s)
      | Has_Binding_type ((pl,s),t) ->
	 Has_Binding_type (((f pl,Place.get_type pl),s),t)
      | Is_Bound_to ((pl,s),(pl',s')) ->
	 Is_Bound_to (((f pl,Place.get_type pl),s),
		      ((f pl',Place.get_type pl'),s'))

    let concretize_action f = function
      | Create (pl,i) -> Create ((f pl,Place.get_type pl),i)
      | Mod_internal ((pl,s),i) -> Mod_internal (((f pl,Place.get_type pl),s),i)
      | Bind ((pl,s),(pl',s')) ->
	 Bind (((f pl,Place.get_type pl),s),((f pl',Place.get_type pl'),s'))
      | Bind_to ((pl,s),(pl',s')) ->
	 Bind_to (((f pl,Place.get_type pl),s),((f pl',Place.get_type pl'),s'))
      | Free (pl,s) -> Free ((f pl,Place.get_type pl),s)
      | Remove pl -> Remove (f pl,Place.get_type pl)

    let concretize_event f (tests,(actions,kasa_side,kasim_side)) =
      (List.map (concretize_test f) tests,
       (List.map (concretize_action f) actions,
	List.map (fun ((pl,s),b) ->
		  (((f pl, Place.get_type pl),s),concretize_binding_state f b))
		 kasa_side,
	List.map (fun (pl,s) -> ((f pl, Place.get_type pl),s)) kasim_side))

    let subst_map_concrete_agent f (id,na as agent) =
      try if f id == id then agent else (f id,na)
      with Not_found -> agent

    let subst_map_site f (ag,s as site) =
      let ag' = f ag in
      if ag==ag' then site else (ag',s)

    let subst_map_agent_in_test f = function
      | Is_Here agent as x ->
	 let agent' = f agent in
	 if agent == agent' then x else Is_Here agent'
      | Has_Internal (site,internal_state) as x ->
	 let site' = subst_map_site f site in
	 if site == site' then x else Has_Internal (site',internal_state)
      | Is_Free site as x ->
	 let site' = subst_map_site f site in
	 if site == site' then x else Is_Free site'
      | Is_Bound site as x ->
	 let site' = subst_map_site f site in
	 if site == site' then x else Is_Bound site'
      | Has_Binding_type (site,binding_type) as x ->
	 let site' = subst_map_site f site in
	 if site == site' then x else Has_Binding_type (site',binding_type)
      | Is_Bound_to (site1,site2) as x ->
	 let site1' = subst_map_site f site1 in
	 let site2' = subst_map_site f site2 in
	 if site1 == site1' && site2 == site2' then x
	 else Is_Bound_to (site1',site2')
    let subst_map_agent_in_concrete_test f x =
      subst_map_agent_in_test (subst_map_concrete_agent f) x
    let subst_agent_in_concrete_test id id' x =
      subst_map_agent_in_concrete_test
	(fun j -> if j = id then id' else j) x
    let rename_abstract_test wk id cc inj x =
      subst_map_agent_in_test (Place.rename wk id cc inj) x

    let subst_map_agent_in_action f = function
      | Create (agent,list) as x ->
	 let agent' = f agent in
	 if agent == agent' then x else Create(agent',list)
      | Mod_internal (site,i) as x ->
	 let site' = subst_map_site f site in
	 if site == site' then x else Mod_internal(site',i)
      | Bind (s1,s2) as x ->
	 let s1' = subst_map_site f s1 in
	 let s2' = subst_map_site f s2 in
	 if s1==s1' && s2==s2' then x else Bind(s1',s2')
      | Bind_to (s1,s2) as x ->
	 let s1' = subst_map_site f s1 in
	 let s2' = subst_map_site f s2 in
	 if s1==s1' && s2==s2' then x else Bind_to(s1',s2')
      | Free site as x ->
	 let site' = subst_map_site f site in
	 if site == site' then x else Free site'
      | Remove agent as x ->
	 let agent' = f agent in
	 if agent==agent' then x else Remove agent'
    let subst_map_agent_in_concrete_action f x =
      subst_map_agent_in_action (subst_map_concrete_agent f) x
    let subst_agent_in_concrete_action id id' x =
      subst_map_agent_in_concrete_action
	(fun j -> if j = id then id' else j) x
    let rename_abstract_action wk id cc inj x =
	 subst_map_agent_in_action (Place.rename wk id cc inj) x

    let subst_map_binding_state f = function
      | (ANY | FREE | BOUND | BOUND_TYPE _ as x) -> x
      | BOUND_to (ag,s) as x ->
	 let ag' = f ag in if ag == ag' then x else BOUND_to (ag',s)
    let subst_map_agent_in_side_effect f (site,bstate as x) =
      let site' = subst_map_site f site in
      let bstate' = subst_map_binding_state f bstate in
       if site == site' && bstate == bstate' then x else (site',bstate')
    let subst_map_agent_in_concrete_side_effect f x =
      subst_map_agent_in_side_effect (subst_map_concrete_agent f) x
    let subst_agent_in_concrete_side_effect id id' x =
      subst_map_agent_in_concrete_side_effect
	(fun j -> if j = id then id' else j) x
    let rename_abstract_side_effect wk id cc inj x =
      subst_map_agent_in_side_effect (Place.rename wk id cc inj) x

    let subst_map_agent_in_event f (tests,(acs,kasa_side,kasim_side)) =
      (Tools.list_smart_map (subst_map_agent_in_test f) tests,
       (Tools.list_smart_map (subst_map_agent_in_action f) acs,
	Tools.list_smart_map (subst_map_agent_in_side_effect f) kasa_side,
	Tools.list_smart_map (subst_map_site f) kasim_side))
    let subst_map_agent_in_concrete_event f x =
      subst_map_agent_in_event (subst_map_concrete_agent f) x
    let subst_agent_in_concrete_event id id' x =
      subst_map_agent_in_concrete_event
	(fun j -> if j = id then id' else j) x
    let rename_abstract_event wk id cc inj x =
      subst_map_agent_in_event (Place.rename wk id cc inj) x

    let with_sigs f = function
      | None -> Format.pp_print_int
      | Some sigs -> f sigs
    let print_concrete_agent ?sigs f (id,ty) =
      Format.fprintf
	f "%a_%i" (with_sigs Signature.print_agent sigs) ty id
    let print_concrete_agent_site ?sigs f ((_,ty as agent),id) =
      Format.fprintf f "%a.%a" (print_concrete_agent ?sigs) agent
		     (with_sigs (fun s -> Signature.print_site s ty) sigs) id
    let print_concrete_test ?sigs f = function
      | Is_Here agent ->
	 Format.fprintf f "Is_Here(%a)" (print_concrete_agent ?sigs) agent
      | Has_Internal (((_,ty),id as site),int) ->
	 Format.fprintf f "Has_Internal(%a~%a)"
			(print_concrete_agent_site ?sigs) site
			(with_sigs
			   (fun s -> Signature.print_internal_state s ty id)
			   sigs) int
      | Is_Free site ->
	 Format.fprintf f "Is_Free(%a)" (print_concrete_agent_site ?sigs) site
      | Is_Bound site ->
	 Format.fprintf f "Is_Bound(%a)" (print_concrete_agent_site ?sigs) site
      | Has_Binding_type (site,(ty,sid)) ->
	 Format.fprintf f "Btype(%a,%t)"
			(print_concrete_agent_site ?sigs) site
			(fun f ->
			 match sigs with
			 | None -> Format.fprintf f "%i.%i" ty sid
			 | Some sigs ->
			    Format.fprintf
			      f "%a.%a" (Signature.print_agent sigs) ty
			      (Signature.print_site sigs ty) sid)
      | Is_Bound_to (site1,site2) ->
	 Format.fprintf f "Is_Bound(%a,%a)"
			(print_concrete_agent_site ?sigs) site1
			(print_concrete_agent_site ?sigs) site2
    let print_concrete_action ?sigs f = function
      | Create ((_,ty as agent),list) ->
	 Format.fprintf
	   f "Create(%a[@[<h>%a@]])" (print_concrete_agent ?sigs) agent
	   (Pp.list Pp.comma
		    (fun f (x,y) ->
		     match sigs with
		     | Some sigs ->
			Signature.print_site_internal_state sigs ty x f y
		     | None ->
			match y with
			| None -> Format.pp_print_int f x
			| Some y ->
			   Format.fprintf f "%i.%i" x y))
	   list
      | Mod_internal (((_,ty),id as site),int) ->
	 Format.fprintf f "Mod(%a~%a)" (print_concrete_agent_site ?sigs) site
			(with_sigs
			   (fun s -> Signature.print_internal_state s ty id)
			   sigs) int
      | Bind (site1,site2) ->
	 Format.fprintf f "Bind(%a,%a)" (print_concrete_agent_site ?sigs) site1
			(print_concrete_agent_site ?sigs) site2
      | Bind_to (site1,site2) ->
	 Format.fprintf f "Bind_to(%a,%a)" (print_concrete_agent_site ?sigs) site1
			(print_concrete_agent_site ?sigs) site2
      | Free site ->
	 Format.fprintf f "Free(%a)" (print_concrete_agent_site ?sigs) site
      | Remove agent ->
	 Format.fprintf f "Remove(%a)" (print_concrete_agent ?sigs) agent

  end

type elementary_rule = {
  rate : Alg_expr.t;
  connected_components : Connected_component.t array;
  removed : Transformation.t list;
  inserted : Transformation.t list;
  consumed_tokens : (Alg_expr.t * int) list;
  injected_tokens : (Alg_expr.t * int) list;
  instantiations : Instantiation.abstract Instantiation.event;
}

type modification =
    ITER_RULE of Alg_expr.t Location.annot * elementary_rule
  | UPDATE of Operator.rev_dep * Alg_expr.t Location.annot
  | SNAPSHOT of Alg_expr.t Ast.print_expr Location.annot list
  | STOP of Alg_expr.t Ast.print_expr Location.annot list
  | CFLOW of
      Connected_component.t * Instantiation.abstract Instantiation.test list
  | FLUX of Alg_expr.t Ast.print_expr Location.annot list
  | FLUXOFF of Alg_expr.t Ast.print_expr Location.annot list
  | CFLOWOFF of Connected_component.t
  | PLOTENTRY
  | PRINT of
      (Alg_expr.t Ast.print_expr Location.annot list *
	 Alg_expr.t Ast.print_expr Location.annot list)

type perturbation =
    { precondition: Alg_expr.t Ast.bool_expr;
      effect : modification list;
      abort : Alg_expr.t Ast.bool_expr option;
      stopping_time : Nbr.t list
    }

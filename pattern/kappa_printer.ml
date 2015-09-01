let alg_expr ?env f alg =
  let sigs = match env with
    | None -> None
    | Some e -> Some e.Environment.signatures in
  let rec aux f = function
    | Expr.BIN_ALG_OP (op, (a,_), (b,_)) ->
       Format.fprintf f "(%a %a %a)" aux a Term.print_bin_alg_op op aux b
    | Expr.UN_ALG_OP (op, (a,_)) ->
       Format.fprintf f "(%a %a)" Term.print_un_alg_op op aux a
    | Expr.STATE_ALG_OP op -> Term.print_state_alg_op f op
    | Expr.CONST n -> Nbr.print f n
    | Expr.ALG_VAR i ->
       Environment.print_alg ?env f i
    | Expr.KAPPA_INSTANCE ccs ->
       Pp.list
	 (fun f -> Format.fprintf f " +@ ")
	 (Pp.array
	    (fun f -> Format.fprintf f "*")
	    (fun _ f cc ->
	     Format.fprintf
	       f "|%a|"
	       (Connected_component.print ?sigs false) cc))
	 f ccs
    | Expr.TOKEN_ID i ->
       Format.fprintf f "|%a|" (Environment.print_token ?env) i
  in aux f alg

let print_expr ?env f e =
  let aux f = function
    | Ast.Str_pexpr str,_ -> Format.fprintf f "\"%s\"" str
    | Ast.Alg_pexpr alg,_ -> alg_expr ?env f alg
  in Pp.list (fun f -> Format.fprintf f ".") aux f e

let print_expr_val ?env alg_val f e =
  let aux f = function
    | Ast.Str_pexpr str,_ -> Format.pp_print_string f str
    | Ast.Alg_pexpr alg,_ ->
       Nbr.print f (alg_val ?env alg)
  in Pp.list (fun f -> Format.pp_print_cut f ()) aux f e

let elementary_rule ?env f r =
  let sigs = match env with
    | None -> None
    | Some e -> Some e.Environment.signatures in
  let pr_alg f a = alg_expr ?env f a in
  let pr_tok f (va,tok) =
    Format.fprintf
      f "%a <- %a"
      (Environment.print_token ?env) tok
      pr_alg va in
  let pr_trans f t =
    Transformations.print ?sigs f t in
  let boxed_cc i f cc =
    let () = Format.pp_open_box f 2 in
    let () = Format.pp_print_int f i in
    let () = Format.pp_print_string f ": " in
    let () = Connected_component.print ?sigs true f cc in
    Format.pp_close_box f () in
  Format.fprintf
    f "@[%a@]@ -- @[@[%a@]@ @[%a@]@]@ ++ @[@[%a@]@ @[%a@]@]@ @@%a"
    (Pp.array Pp.comma boxed_cc) r.Primitives.connected_components
    (Pp.list Pp.comma pr_trans) r.Primitives.removed
    (Pp.list Pp.space pr_tok) r.Primitives.consumed_tokens
    (Pp.list Pp.comma pr_trans) r.Primitives.inserted
    (Pp.list Pp.space pr_tok) r.Primitives.injected_tokens
    (alg_expr ?env) r.Primitives.rate

let modification ?env f = function
  | Primitives.PRINT (nme,va) ->
     Format.fprintf f "$PRINTF %a <%a>"
		    (print_expr ?env) nme (print_expr ?env) va
  | Primitives.PLOTENTRY -> Format.pp_print_string f "$PLOTENTRY"
  | Primitives.ITER_RULE ((n,_),rule) ->
     if rule.Primitives.inserted = [] then
       if rule.Primitives.connected_components = [||] then
	 match rule.Primitives.injected_tokens with
	 | [ va, id ] ->
	    Format.fprintf f "%a <- %a"
			   (Environment.print_token ?env) id
			   (alg_expr ?env) va
	 | _ -> assert false
       else
	 let sigs = match env with
	   | None -> None
	   | Some e -> Some e.Environment.signatures in
	 let boxed_cc i f cc =
	   let () = Format.pp_open_box f 2 in
	   let () = Format.pp_print_int f i in
	   let () = Format.pp_print_string f ": " in
	   let () = Connected_component.print ?sigs false f cc in
	   Format.pp_close_box f () in
	 Format.fprintf f "$DEL %a %a" (alg_expr ?env) n
			(Pp.array Pp.comma boxed_cc)
			rule.Primitives.connected_components
     else
       Format.fprintf f "$APPLY %a %a" (alg_expr ?env) n
		      (elementary_rule ?env) rule (* TODO Later *)
  | Primitives.UPDATE (d_id,(va,_)) ->
     begin
       match d_id with
       | Term.ALG id ->
	  Format.fprintf f "$UPDATE %a %a"
			 (Environment.print_alg ?env) id
       | Term.RULE id ->
	  Format.fprintf f "$UPDATE '%a' %a" (Environment.print_rule ?env) id
       | (Term.KAPPA _ | Term.TIME | Term.EVENT
	  | Term.ABORT _ | Term.PERT _ | Term.TOK _) ->
	  Format.fprintf f "$UPDATE '%a' %a" Term.print_dep_type d_id
     end (alg_expr ?env) va
  | Primitives.SNAPSHOT fn ->
     Format.fprintf f "SNAPSHOT %a" (print_expr ?env) fn
  | Primitives.STOP fn ->
     Format.fprintf f "STOP %a" (print_expr ?env) fn
  | Primitives.FLUX fn ->
     Format.fprintf f "$FLUX %a [true]" (print_expr ?env) fn
  | Primitives.FLUXOFF fn ->
     Format.fprintf f "$FLUX %a [false]" (print_expr ?env) fn
  | Primitives.CFLOW id ->
     let nme = (*try Environment.rule_of_num id env
	       with Not_found -> Environment.kappa_of_num id env*)
       string_of_int id
     in Format.fprintf f "$TRACK '%s' [true]" nme
  | Primitives.CFLOWOFF id ->
     let nme = (*try Environment.rule_of_num id env
	       with Not_found -> Environment.kappa_of_num id env*)
       string_of_int id
     in Format.fprintf f "$TRACK '%s' [false]" nme

let perturbation ?env f pert =
  let aux f =
    Format.fprintf f "%a do %a"
		   (Expr.print_bool (alg_expr ?env)) pert.Primitives.precondition
		   (Pp.list Pp.colon (modification ?env)) pert.Primitives.effect
  in
  match pert.Primitives.abort with
  | None -> Format.fprintf f "%%mod: %t@." aux
  | Some ab ->
     Format.fprintf f "%%mod: repeat %t until %a@." aux
		    (Expr.print_bool (alg_expr ?env)) ab

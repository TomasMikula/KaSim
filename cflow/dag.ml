(**
  * dag.ml 
  *
  * Dag computation and canonical form 
  *
  * Jérôme Feret, projet Abstraction, INRIA Paris-Rocquencourt
  * Jean Krivine, Université Paris-Diderot, CNRS 
  * 
  * KaSim
  * Jean Krivine, Université Paris Dederot, CNRS 
  *  
  * Creation: 22/03/2012
  * Last modification: 24/04/2012
  * * 
  * Some parameters references can be tuned thanks to command-line options
  * other variables has to be set before compilation   
  *  
  * Copyright 2011,2012 Institut National de Recherche en Informatique et   
  * en Automatique.  All rights reserved.  This file is distributed     
  * under the terms of the GNU Library General Public License *)


module type Dag = 
  sig
    module S:Generic_branch_and_cut_solver.Solver
      
    type graph 
    type canonical_form 

    val graph_of_grid: (Causal.grid -> S.PH.B.PB.CI.Po.K.H.error_channel * graph) S.PH.B.PB.CI.Po.K.H.with_handler
    val dot_of_graph: (graph -> S.PH.B.PB.CI.Po.K.H.error_channel) S.PH.B.PB.CI.Po.K.H.with_handler
    val canonicalize: (graph -> S.PH.B.PB.CI.Po.K.H.error_channel * canonical_form) S.PH.B.PB.CI.Po.K.H.with_handler
    val compare: canonical_form -> canonical_form -> int 
      
    val print_canonical_form: (canonical_form -> S.PH.B.PB.CI.Po.K.H.error_channel) S.PH.B.PB.CI.Po.K.H.with_handler
    val print_graph: (graph -> S.PH.B.PB.CI.Po.K.H.error_channel) S.PH.B.PB.CI.Po.K.H.with_handler 
  end 


module Dag = 
  (
    struct 
      module S=Generic_branch_and_cut_solver.Solver
      module H=S.PH.B.PB.CI.Po.K.H
      module A=Mods.DynArray 

      type graph = 
          { 
            root: int; 
            labels: string A.t ;
            pred: int list A.t ;
            succ: int list A.t ;
            conflict_pred: int list A.t; 
            conflict_succ: int list A.t;
          }

      let dummy_graph = 
        {
          root = 0 ;
          labels = A.make 1 "" ;
          pred = A.make 1 [] ;
          succ = A.make 1 [] ;
          conflict_pred = A.make 1 [] ; 
          conflict_succ = A.make 1 [] ;
        }

      type edge_kind = Succ | Conflict 
      type label = string
      type position = int 
      type key = 
        | Fresh of label
        | Former of position 
        | Stop

      type canonical_form = key list

      let dummy_cannonical_form = []

          
      let print_graph parameter handler error graph = 
        let _ = Printf.fprintf parameter.H.out_channel "****\ngraph\n****" in 
        let _ = Printf.fprintf parameter.H.out_channel "Root: %i\n" graph.root in 
        let _ = Printf.fprintf parameter.H.out_channel "Labels:\n" in 
        let _ = A.iteri (Printf.fprintf parameter.H.out_channel "Node %i,Label %s\n") graph.labels in 
        let _ = Printf.fprintf parameter.H.out_channel "Succ:\n" in 
        let _ = 
          A.iteri 
            (fun i l -> 
              List.iter (Printf.fprintf parameter.H.out_channel "%i -> %i\n" i) l 
            ) 
            graph.succ 
        in 
        let _ = 
          A.iteri 
            (fun i l   -> 
              List.iter (Printf.fprintf parameter.H.out_channel "%i <- %i\n" i) l 
            ) 
            graph.pred
        in 
        let _ = Printf.fprintf parameter.H.out_channel "Conflicts:\n" in 
        let _ = 
          A.iteri 
            (fun i l ->  
              List.iter 
                (Printf.fprintf parameter.H.out_channel "%i --| %i\n" i)
                l
            )
            graph.conflict_succ
        in 
          let _ = 
          A.iteri 
            (fun i l  ->  
              List.iter 
                (Printf.fprintf parameter.H.out_channel "%i |--  %i\n" i)
                l
            )
            graph.conflict_pred
          in 
        let _ = Printf.fprintf parameter.H.out_channel "****\n\n" in 
        error 

      let print_elt log elt = 
        match 
          elt 
        with 
          | Stop -> Printf.fprintf log "STOP\n" 
          | Former i -> Printf.fprintf log "Pointer %i\n" i 
          | Fresh s -> Printf.fprintf log "Event %s\n" s 

      let print_canonical_form parameter handler error graph = 
        let _ =
          List.iter 
            (print_elt parameter.H.out_channel)
            graph 
        in error 

      let label handler e = 
	match e with
	  | Causal.OBS mix_id -> Environment.kappa_of_num mix_id handler.H.env
	  | Causal.PERT p_id -> Environment.pert_of_num p_id handler.H.env
	  | Causal.RULE r_id -> Dynamics.to_kappa (State.rule_of_id r_id handler.H.state) handler.H.env
	  | Causal.INIT -> "intro"

      let compare_elt x y = 
        match x,y with 
          | Stop,Stop -> 0 
          | Stop,_ -> -1 
          | _,Stop -> +1
          | Former i, Former j -> compare i j 
          | Former _,_ -> -1
          | _,Former _ -> +1
          | Fresh s,Fresh s' -> compare s s'

      let rec aux l1 l2 = 
        match l1,l2 
        with 
          | [],[] -> 0 
          | [], _ -> -1 
          | _ ,[] -> +1 
          | t::q,t'::q' -> 
            let cmp = compare_elt t t' in 
            if cmp = 0 
              then aux q q' 
            else cmp 
      
      let compare x y = aux x y 


      let graph_of_grid parameter handler error grid = 
        let ids = Hashtbl.fold (fun key _ l -> key::l) grid.Causal.flow [] in
        let label = label handler in 
        let config = Causal.cut ids grid in 
        let labels = A.make 1 "" in 
        let set =  
          Mods.IntMap.fold
            (fun i atom  -> 
              let _ = A.set labels i (label atom.Causal.kind) in 
              Mods.IntSet.add i 
            )
            config.Causal.events
            Mods.IntSet.empty 
        in 
        let add_to_list_array i j a = 
          try 
            let old = 
              try 
                A.get a i 
              with 
                | Not_found -> []
            in 
            A.set a i  (j::old) 
          with 
            | _ -> A.set a i [j]
        in 
        let add i j s p = 
          let _ = add_to_list_array i j s in 
          let _ = add_to_list_array j i p in 
          ()
        in 
        let succ  = A.make 1 [] in 
        let pred = A.make 1 [] in 
        let root = 
         Mods.IntMap.fold
           (fun i s set ->
             if Mods.IntSet.is_empty s
             then set 
             else 
               let set  = 
                 Mods.IntSet.fold
                   (fun j -> 
                     let _ = add j i succ pred in 
                   Mods.IntSet.remove j)
                   s
                   set
               in 
               set)
           config.Causal.prec_1
           set 
        in 
        let conflict_pred = A.make 1 [] in 
        let conflict_succ = A.make 1 [] in 
        let root = 
          Mods.IntMap.fold
            (fun i s root ->
              if Mods.IntSet.is_empty s 
              then set 
              else 
                let root = 
                  Mods.IntSet.fold 
                    (fun j -> 
                      let _ = add j i conflict_succ conflict_pred in 
                    Mods.IntSet.remove j)
                    s
                    root 
                in 
                root)
            config.Causal.conflict 
            root
        in 
        if Mods.IntSet.is_empty root
        then 
          error,dummy_graph 
        else 
          error,{ 
            root = Mods.IntSet.min_elt root ;
            labels = labels ;
            succ = succ ;
            pred = pred ;
            conflict_succ = conflict_succ ;
            conflict_pred = conflict_pred 
          }

      let concat list1 list2 = 
        let rec aux list1 list2 = 
          match list2 
          with 
            | [] -> list1 
            | t::q -> aux (t::list1) q 
        in 
        aux list2 (List.rev list1)

      let canonicalize parameter handler error graph = 
        let asso = Mods.IntMap.empty in 
        let label i = 
          try 
            A.get graph.labels i 
          with 
            | _ -> "" 
        in 
        let rec visit i map fresh_pos = 
          let pos = 
            try 
              Some (Mods.IntMap.find i map)
            with 
                Not_found -> None 
          in 
          match 
            pos 
          with 
            | Some i -> [Former i],map,fresh_pos
            | None -> 
              let map = Mods.IntMap.add i fresh_pos map in 
              let fresh_pos = fresh_pos + 1 in 
              let sibbling1 = 
                try 
                  A.get graph.pred i 
                with 
                  | Not_found -> []
              in 
              let sibbling2 = 
                try 
                  A.get graph.conflict_pred i 
                with 
                  | Not_found -> []
              in 
              let rec best_sibbling m f candidates not_best record = 
                match candidates 
                with 
                  | [] -> not_best,record 
                  | t::q -> 
                    let encoding,map,fresh =
                      visit t m f
                    in 
                    let better,best = 
                      begin 
                      match record 
                      with 
                        | None -> true,None
                        | Some (best,best_encoding,_,_) -> 
                          (compare encoding best_encoding <0),Some best
                      end 
                    in 
                    if better 
                    then 
                      best_sibbling m f q (match best with None -> not_best | Some best -> best::not_best) (Some(t,encoding,map,fresh))
                    else 
                      best_sibbling m f q (t::not_best) record 
              in 
              let rec aux m f l sol = 
                let not_best,record = 
                  best_sibbling m f l [] None
                in 
                match record 
                with 
                  | None -> map,fresh_pos,sol  
                  | Some (_,best,map,fresh_pos) -> 
                    aux map fresh_pos not_best (concat sol best)
              in 
              let list = [Fresh (label i)] in 
              let map,fresh_pos,list = aux 
                map 
                fresh_pos 
                sibbling1 
                list in 
              let list = concat list [Stop] in 
              let map,fresh_pos,list = aux map fresh_pos sibbling2 list in
              let list = concat list [Stop] in 
              list,map,fresh_pos  
        in 
        let rep,_,_= visit graph.root asso 0  
        in error,rep
     
      let dot_of_graph parameter handler error graph = error  

        
    end:Dag)
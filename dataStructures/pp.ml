open Format

let list pr_sep pr_el f l =
  let rec aux f = function
  | [] -> ()
  | [el] -> pr_el f el
  | h :: t -> fprintf f "%a%t%a" pr_el h pr_sep aux t
  in aux f l

let set elements pr_sep pr_el f set =
  list pr_sep pr_el f (elements set)

let string f s = fprintf f "%s" s
let int f i = fprintf f "%i" i
let comma f = fprintf f ", "
let colon f = fprintf f "; "
let space f = fprintf f " "
let empty f = fprintf f ""

let position f (beg_pos,end_pos) =
  let () = assert (beg_pos.Lexing.pos_fname = end_pos.Lexing.pos_fname) in
  let pr_l f =
    if beg_pos.Lexing.pos_lnum = end_pos.Lexing.pos_lnum
    then fprintf f "line %i" beg_pos.Lexing.pos_lnum
    else fprintf f "lines %i-%i" beg_pos.Lexing.pos_lnum end_pos.Lexing.pos_lnum
  in
  fprintf f "File \"%s\", %t, characters %i-%i:" beg_pos.Lexing.pos_fname pr_l
	  (beg_pos.Lexing.pos_cnum - beg_pos.Lexing.pos_bol)
	  (end_pos.Lexing.pos_cnum - end_pos.Lexing.pos_bol)

let error pr (x,pos) =
  eprintf "%a:@ %a@." position pos pr x

let list_to_string pr_sep pr_el () l =
  let rec aux () = function
  | [] -> ""
  | [el] -> pr_el () el
  | h :: t -> sprintf "%a%t%a" pr_el h pr_sep aux t
  in aux () l

let set_to_string elements pr_sep pr_el () set =
  list_to_string pr_sep pr_el () (elements set)
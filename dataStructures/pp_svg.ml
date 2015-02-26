type store = {
  file: string;
  title: string;
  descr: string;
  legend: string array;
  mutable points: (float * Nbr.t array) list;
}

let new_file name =
  let chan = Tools.kasim_open_out name in
  let f = Format.formatter_of_out_channel chan in
  let () = Format.fprintf f "@[<v><?xml version=\"1.0\"?>@," in
  let () =
    Format.fprintf
      f "@[<!DOCTYPE@ svg@ PUBLIC@ \"-//W3C//DTD SVG 1.1//EN\"@ " in
  let () =
    Format.fprintf
      f "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">@]@,@," in
  (f,chan)

let close_file form chan =
  let () = Format.fprintf form "@]@." in
  close_out chan

let style f =
  let () = Format.fprintf f "<style type=\"text/css\" >@," in
  let () = Format.fprintf f "<![CDATA[@," in
  let () = Format.fprintf f "@[<hv 2>#legend text {@," in
  let () = Format.fprintf f "text-anchor:end;@ baseline-shift:-.4em;@," in
  let () = Format.fprintf f "}@]@," in
  let () = Format.fprintf f "@[<hv 2>#axis_t text {@," in
  let () = Format.fprintf f "text-anchor:middle;@ baseline-shift:-1em;@," in
  let () = Format.fprintf f "}@]@," in
  let () = Format.fprintf f "@[<hv 2>#axis_va text {@," in
  let () = Format.fprintf f "text-anchor:end;@ baseline-shift:-.4em;@," in
  let () = Format.fprintf f "}@]@," in
  let () =
    Format.fprintf f "@[<hv 2>#axes {@,color:black;@,stroke:currentColor;" in
  let () = Format.fprintf f "@,stroke-size:1px;@,}@]@," in
  let () =
    Format.fprintf f "@[<hv 2>#axes text {@,stroke:none;@,fill:currentColor;@,}@]@," in
(*  let () =
    Format.fprintf f "@[<hv 2>#data use:hover {@,fill:green;@,}@]@," in*)
  Format.fprintf f "]]>@,</style>@,@,"

let colors = [|"blue";"purple";"green";"peru"|]
let styles = [|"plus";"cross";"point"|]
let defs f =
  let () = Format.fprintf f "<defs>@," in
  let () = Format.fprintf
	     f "<path id=\"plus\" class=\"point\" stroke=\"currentColor\"" in
  let () = Format.fprintf f " d=\"M-3.5,0 h7 M0,-3.5 v7\"/>@," in
  let () = Format.fprintf
	     f "<path id=\"cross\" class=\"point\" stroke=\"currentColor\"" in
  let () =
    Format.fprintf f " d=\"M-3.5,-3.5 L3.5,3.5 M3.5,-3.5 L-3.5,3.5\"/>@," in
  let () =
    Format.fprintf f "<circle id=\"point\" class=\"point\" r=\"2.5\"" in
  let () = Format.fprintf f " stroke=\"none\" fill=\"currentColor\"/>@," in
  Format.fprintf f "</defs>@,@,"

let legend w f a =
  let pp_line i f s =
    let () = Format.fprintf f "@[<h><text x=\"%i\" y=\"%i\">%s</text>@]@,"
			    (w-15) (10+i*15) s in
    Format.fprintf
      f "<use xlink:href=\"#%s\" style=\"color:%s\" x=\"%i\" y=\"%i\"/>"
      styles.(i mod Array.length styles) colors.(i mod Array.length colors)
      (w-7) (10+i*15) in
  Format.fprintf f "@[<hv 2><g id=\"legend\">@,%a@]</g>@,@,"
		 (Pp.array ~trailing:Pp.cut Pp.cut pp_line) a

let get_limits l =
  let rec aux t_max va_min va_max = function
    | [] ->
       if Nbr.is_equal va_min va_max then
	 t_max,Nbr.pred va_min, Nbr.succ va_max
       else
	 t_max,Nbr.min va_min (Nbr.I 0),va_max
    | (t,va)::q ->
       aux (max t t_max) (Array.fold_left Nbr.min va_min va)
	   (Array.fold_left Nbr.max va_max va) q in
  match l with
  | [] -> failwith "No data to plot in Pp_svg"
  | (_,va)::_ when Array.length va = 0 ->
     failwith "No data to plot in Pp_svg"
  | (t,va)::q -> aux t (Array.fold_left min va.(0) va)
		     (Array.fold_left max va.(0) va) q

let draw_in_data ((t_max,va_min,va_max),(zero_w,zero_h,draw_w,draw_h)) =
  let delta_va = Nbr.to_float (Nbr.sub va_max va_min) in
  let zero_w' = float_of_int zero_w in
  let zero_h' = float_of_int zero_h in
  let draw_w' = float_of_int draw_w in
  let draw_h' = float_of_int draw_h in
  fun f x y -> f (zero_w' +. ((x *. draw_w') /. t_max))
	       (zero_h' -.
		  ((Nbr.to_float (Nbr.sub y va_min) *. draw_h') /. delta_va))

let graduation_step draw_l min_grad_l va_min va_max =
  let delta_va = Nbr.to_float (Nbr.sub va_max va_min) in
  let nb_grad = ceil (float draw_l /. float min_grad_l) in
  let exact_step = delta_va /. nb_grad in
  let delta_grad = 10. ** (log10 exact_step) in
  let va_min' =
    Nbr.F (delta_grad *. floor ((Nbr.to_float va_min) /. exact_step)) in
  let va_max' =
    Nbr.F (delta_grad *. ceil ((Nbr.to_float va_max) /. exact_step)) in
  (va_min',int_of_float nb_grad,delta_grad,va_max')

let axis (w,h) (b_op,b_w,b_h) f l =
  let (t_max,va_min,va_max as limits) = get_limits l in
  let data_w = w - (b_op + b_w) in
  let data_h = h - (b_op + b_h) in
  let (_,nb_w,grad_w,t_max') =
    graduation_step data_w b_w (Nbr.F 0.) (Nbr.F t_max) in
  let (va_min',nb_h,grad_h,va_max') =
    graduation_step data_h b_w va_min va_max in
  let draw_fun = draw_in_data ((Nbr.to_float t_max',va_min',va_max'),
			       (b_w,h-b_h,data_w,data_h)) in
  let () = Format.fprintf f "<g id=\"axes\">@," in
  let () =
    Format.fprintf f "@[<hv 2><g id=\"axis_va\">@," in
  let () = Format.fprintf f "<title>Observable values</title>@," in
  let () = Format.fprintf f "@[<><path d=\"M %i,%i L %i,%i\"/>@]@,"
			  b_w b_op b_w (data_h+b_op) in
  let () =
    Tools.iteri
      (fun i ->
       let v = grad_h *. float i in
       draw_fun (fun x y ->
		 let () = Format.fprintf f "<text x=\"%f\" y=\"%f\">%.3F</text>@,"
					 (x -. 8.) y v in
		 Format.fprintf f "<line x1=\"%f\" y1=\"%f\" x2=\"%f\" y2=\"%f\"/>@,"
				(x -. 5.) y (x +. 5.) y)
		0. (Nbr.F v)) (succ nb_h) in
  let () =
    Format.fprintf f "@]</g>@,@[<hv 2><g id=\"axis_t\">@," in
  let () = Format.fprintf f "<title>Time in second</title>@," in
  let () =
    Format.fprintf f "@[<><path d=\"M %i,%i L %i,%i\"/>@]@,"
		   b_w (h-b_h) (w-b_op) (h-b_h) in
  let () =
    Tools.iteri
      (fun i ->
       let v = grad_w *. float i in
       draw_fun (fun x y ->
		 let () = Format.fprintf f "<text x=\"%f\" y=\"%f\">%.3F</text>@,"
					 x (y +. 8.) v in
		 Format.fprintf
		   f "<line x1=\"%f\" y1=\"%f\" x2=\"%f\" y2=\"%f\"/>@,"
		   x (y -. 5.) x (y +. 5.))
		v va_min') (succ nb_w) in
  let () = Format.fprintf f "@]</g>@,</g>@,@," in
  draw_fun

let data draw_fun l f p =
  let one_point s t i f va =
    draw_fun (fun x y ->
	      let () =
		Format.fprintf
		  f "@[<><use xlink:href=\"#%s\" x=\"%f\" y=\"%f\">@,"
		  styles.(i mod Array.length styles) x y in
	      Format.fprintf f "<title>%s t=%F v=%a</title>@,</use>@]"
			     s t Nbr.print va
	     ) t va in
  Format.fprintf
    f "<g id=\"data\">@,%a</g>@,@,"
    (Pp.array Pp.cut
	      (fun i f s ->
	       Format.fprintf
		 f "@[<hv 2><g id=\"data_%i\" style=\"color:%s\">@,%a@]</g>"
		 i colors.(i mod Array.length colors)
			    (Pp.list ~trailing:Pp.cut Pp.cut
				     (fun f (t,e) -> one_point s t i f e.(i)))
			    p)) l

let draw (w,h as size) border f s =
  let () = Format.fprintf
	     f "@[<svg@ xmlns=\"http://www.w3.org/2000/svg\"@ " in
  let () = Format.fprintf
	     f "xmlns:xlink=\"http://www.w3.org/1999/xlink\"@ " in
  let () = Format.fprintf
	     f "width=\"%i\"@ height=\"%i\">@]@," w h in
  let () = Format.fprintf f "<title>%s</title>@,<descr>%s</descr>@,@,"
			  s.title s.descr in
  let () = style f in
  let () = defs f in
  let draw_fun = axis size border f s.points in
  let () = legend w f s.legend in
  let () = data draw_fun s.legend f s.points in
  Format.fprintf f "</svg>"

let to_file s =
  let (form,chan) = new_file s.file in
  let size = (800,600) in
  let border = (10,70,25) in
  let () = draw size border form s in
  close_file form chan
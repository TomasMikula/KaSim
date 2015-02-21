open State
open Mods
open ExceptionDefn

type opened = {
  desc:out_channel;
  form:Format.formatter;
  mutable last_point : int
}

type t = Wait of string | Ready of opened

let plotDescr = ref (Wait "__dummy")

let create filename = plotDescr := Wait filename

let set_up filename env counter ?time state =
  let d_chan = Tools.kasim_open_out filename in
  let d = Format.formatter_of_out_channel d_chan in
  let () = print_observables_header d state in
  let () = print_observables_values d env counter state in
  plotDescr :=
    Ready { desc=d_chan; form=d; last_point = 0 }

let close counter =
  match !plotDescr with
  | Wait _ -> ()
  | Ready plot ->
     let n = ref (!Parameter.progressBarSize - counter.Counter.ticks) in
     let () = while !n > 0 do
		Format.printf "%c" !Parameter.progressBarSymbol ;
		n := !n-1
	      done in
     close_out plot.desc

let next_point counter time_increment =
  match counter.Counter.dT with
  | Some dT ->
     int_of_float
       ((counter.Counter.time +. time_increment -. counter.Counter.init_time)
	/. dT)
  | None ->
     match counter.Counter.dE with
     | None -> 0
     | Some dE ->
	(counter.Counter.events - counter.Counter.init_event) / dE

let set_last_point plot p = plot.last_point <- p

let plot_now env counter ?time state =
  match !plotDescr with
  | Wait f -> set_up f env counter ?time state
  | Ready plot ->
     print_observables_values plot.form env counter ?time state

let fill state counter env time_increment =
  let () =
    match !plotDescr with
    | Wait _ -> ()
    | Ready plot ->
       let next = next_point counter time_increment in
       let last = plot.last_point in
       let n = next - last in
       let () = set_last_point plot next in
       match counter.Counter.dE with
       | Some dE ->
	  if n>1 then
	    invalid_arg (Printf.sprintf "Plot.fill: invalid increment %d" n)
	  else
	    if n <> 0
	    then plot_now env counter state
       | None ->
	  match counter.Counter.dT with
	  | None -> ()
	  | Some dT ->
	     let n = ref n
	     and output_time = ref ((float_of_int last) *. dT) in
	     while (!n > 0) && (Counter.check_output_time counter !output_time) do
	       output_time := !output_time +. dT ;
	       Counter.tick counter !output_time counter.Counter.events ;
	       plot_now env counter ~time:!output_time  state;
	       n:=!n-1 ;
	     done in
  Counter.tick counter counter.Counter.time counter.Counter.events

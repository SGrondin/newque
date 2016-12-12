open Core.Std
open Lwt

type t =
  | Multiple of string array
  | Atomic of string array
[@@deriving sexp]

type flat =
  | F_single of string [@key 1]
  | F_atomic of string array [@key 2]
[@@deriving protobuf, sexp]

let of_string_array ~atomic messages =
  begin match atomic with
    | false -> Multiple messages
    | true -> Atomic messages
  end

let of_string ~format ~mode ~splitter str =
  let open Http_format in
  match format with
  | Json ->
    let open Json_obj_j in
    begin match Util.parse_sync input_of_string str with
      | (Error _) as err -> err
      | Ok { atomic; messages } -> Ok (of_string_array ~atomic messages)
    end
  | Plaintext ->
    let arr = begin match mode with
      | `Single -> Multiple [| str |]
      | `Multiple -> of_string_array ~atomic:false (Array.of_list (splitter str))
      | `Atomic -> of_string_array ~atomic:true (Array.of_list (splitter str))
    end in
    Ok arr

let of_stream ~format ~mode ~splitter ~buffer_size stream =
  let open Http_format in
  match format with
  | Json ->
    let%lwt str = Util.stream_to_string ~buffer_size stream in
    begin match of_string ~format ~mode ~splitter str with
      | Error str -> failwith str
      | Ok messages -> return messages
    end
  | Plaintext ->
    begin match mode with
      | `Single ->
        let%lwt s = Util.stream_to_string ~buffer_size stream in
        return (Multiple [| s |])
      | `Multiple ->
        let%lwt arr = Util.stream_to_array ~splitter stream in
        return (Multiple arr)
      | `Atomic ->
        let%lwt arr = Util.stream_to_array ~splitter stream in
        return (Atomic arr)
    end

let serialize_full msg =
  let flattened = match msg with
    | Multiple m -> Array.map m ~f:(fun x -> F_single x)
    | Atomic m -> [| F_atomic m |]
  in
  Array.map flattened ~f:(fun x -> Protobuf.Encoder.encode_exn flat_to_protobuf x)

let serialize_raw msg =
  match msg with
  | Multiple m -> m
  | Atomic m -> m

let parse_full_exn blob =
  try
    match Protobuf.Decoder.decode_exn flat_from_protobuf blob with
    | F_single s -> [| s |]
    | F_atomic m -> m
  with
  | Protobuf.Decoder.Failure err ->
    let str = Protobuf.Decoder.error_to_string err in
    failwith (sprintf "Unable to parse the wrapped messages, did it get corrupted? Reason: %s" str)

let length ~raw msg =
  match msg with
  | Multiple m -> Array.length m
  | Atomic m when raw -> Array.length m
  | Atomic _ -> 1

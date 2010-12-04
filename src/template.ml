open Printf
open Cow

let bar cur =
  let bars = [
    "/","Home";
    "/blog/","Blog"; 
    "http://github.com/avsm/mirage", "Code";
    "/resources/","Resources";
    "/about/","About"
  ] in
  let one (href, title) =
    if title=cur then
      <:html<
        <li><a class="current_page" href=$str:href$>$str:title$</a></li>
      >>
    else
      <:html<
        <li><a href=$str:href$>$str:title$</a></li>
      >> in
  <:html< <ul>$list:List.map one bars$</ul> >>

let t ?extra_header title page content =
  match Filesystem_templates.t "main.html" with
    | Some main_html ->
      let templates = [
        "TITLE"       , <:html< $str:title$ >>;
        "BAR"         , <:html< $bar title$ >>;
        "EXTRA_HEADER", <:html< $opt:extra_header$ >>;
        "CONTENT"     , <:html< $content$ >>;
      ] in
      Html.of_string ~templates main_html
    | None ->
      Printf.eprintf "[ERROR] Cannot find tmp/main.html\n";
      assert false




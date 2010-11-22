open Printf
open Http
open Log
open Lwt

let md_file f =
  let f = match Filesystem_templates.t f with |Some x -> x |None -> "" in
  let md = Markdown.parse_text f in
  Markdown_html.t md

let md_xml f =
  let ibuf = Html.to_string (md_file f) in
  ibuf
 
let col_files l r = 
  let h = <:html< 
     <div class="left_column">
       <div class="summary_information"> $md_file l$ </div>
     </div>
     <div class="right_column"> $md_file r$ </div>
  >> in 
  Html.to_string h 

module Index = struct
  let body = col_files "intro.md" "ne.md"
  let t = Template.t "index" body
end

module Resources = struct
  let body = col_files "docs.md" "papers.md"
  let t = Template.t "resources" body
end 

module About = struct
  let body = col_files "status.md" "ne.md"
  let t = Template.t "about" body
end

module Blog = struct
  open Blog

  let str_of_month = function
  |1 -> "Jan" |2 -> "Feb" |3 -> "Mar" |4 -> "Apr" |5 -> "May"
  |6 -> "Jun" |7 -> "Jul" |8 -> "Aug" |9 -> "Sep" |10 -> "Oct"
  |11 -> "Nov" |12 -> "Dec" |_ -> "???"

  (* Convert a blog record into an Html.t fragment *)
  let html_of_ent e =
    let author = match e.author.Atom.uri with
      |None -> <:html< $str:e.author.Atom.name$ >>
      |Some uri -> <:html< <a href= $str:uri$ > $str:e.author.Atom.name$ </a> >> in
    let permalink = sprintf "%s/blog/%s" Config.baseurl e.permalink in
    let year,month,day,hour,minute = e.updated in
    <:html<
      <div class="entryDate">
       <span class="postMonth">$str:str_of_month month$</span>
       <span class="postDay">$int:day$</span>
       <span class="postYear">$int:year$</span>
      </div>

      <div class="blog_entry_heading">
        <div class="blog_entry_title">
         <a href=$str:permalink$>
          $str:e.subject$
         </a>
        </div>
        <div class="blog_entry_info">
          <i> Posted by $author$ </i>
        </div>
      </div>
      <div class="blog_entry_body"> $md_file e.body$ 
       <br />
       </div>
    >>

  (* Generate the category bar Html.t fragment *)
  let html_of_category (l1, l2l) =
    let l2h = List.map (fun l2 ->
       match Blog.num_l2_categories l1 l2 with 
       |0 -> <:html< <div class="blog_bar_l2">$str:l2$</div> >>
       |nl2 ->
         let num = <:html< <i>$str:sprintf "(%d)" nl2$</i> >> in
         let url = sprintf "\"%s/tag/%s/%s\"" Config.baseurl l1 l2 in
         <:html< <div class="blog_bar_l2"><a href=$str:url$>$str:l2$</a>$num$</div> >>
    ) l2l in
    let url = sprintf "\"%s/tag/%s\"" Config.baseurl l1 in
    let l1h = match Blog.num_l1_categories l1 with
    | 0 -> <:html< <div class="blog_bar_l1">$str:l1$</div> >>
    | nl1 -> <:html< <div class="blog_bar_l1"><a href=$str:url$>$str:l1$</a></div> >> in
    <:html<
      $l1h$
      $list:l2h$
    >>

  (* The full right bar in blog *)
  let right_bar =
    let url = sprintf "\"%s/blog/\"" Config.baseurl in
    <:html<
      <div class="blog_bar">
        <div class="blog_bar_l0"><a href=$str:url$>Index</a></div>
         $list:List.map html_of_category Blog.categories$
      </div>
    >>

  (* From a list of Html.t entries, wrap it in the Blog Html.t *)
  let body_of_entries ents = <:html<
    <div class="left_column_blog">
      <div class="summary_information">
        $list:ents$
       </div>
    </div>
    <div class="right_column_blog">
       $right_bar$
    </div>
  >>

  (* Make a full Html.t including RSS link and headers from a list
     of Html.t entry fragments *)
  let html_of_entries title ents =
    let url = sprintf "\"%s/blog/atom.xml\"" Config.baseurl in
    let headers = Html.to_string <:html< 
     <link rel="alternate" type="application/atom+xml" href=$str:url$ /> >> in
    Template.t ~headers ("blog" ^ (match title with None -> "" |Some x -> " :: " ^ x)) (Html.to_string ents)

  (* Main blog page Html.t fragment with all blog posts *)
  let main_page =
    let index_entries = List.sort compare (List.map html_of_ent Blog.entries) in
    html_of_entries None (body_of_entries index_entries)

  let ent_bodies = Hashtbl.create 1
  let _ =
    List.iter (fun ent ->
      let title = Some ent.subject in
      let html = body_of_entries [html_of_ent ent] in
      Hashtbl.add ent_bodies ent.permalink (html_of_entries title html);
    ) Blog.entries

  let lt1_bodies = Hashtbl.create 1
  let _ =
    List.iter (fun (lt1,_) ->
       let title = Some lt1 in
       let ents = List.filter (fun e ->
          let c,_ = e.category in c = lt1
       ) Blog.entries in
       let html = body_of_entries (List.map html_of_ent ents) in
       Hashtbl.add lt1_bodies lt1 (html_of_entries title html);
    ) Blog.categories

  let lt2_bodies = Hashtbl.create 1
  let _ =
    List.iter (fun (lt1,lt2s) ->
      List.iter (fun lt2 ->
         let title = Some (lt1 ^ " :: " ^ lt2) in
         let ents = List.filter (fun e ->
           let _,c = e.category in c = lt2
         ) Blog.entries in
         let html = body_of_entries (List.map html_of_ent ents) in
         Hashtbl.add lt2_bodies lt2 (html_of_entries title html);
      ) lt2s
    ) Blog.categories

  let atom_feed = 
    let f = Blog.atom_feed md_xml Blog.entries in
    Atom.string_of_feed f

  let not_found x = sprintf "Not found: %s (known links: %s)"
     (String.concat " ... " x) 
     (String.concat " " 
       (Hashtbl.fold (fun k v a -> k :: a) 
         ent_bodies []))

  let t = function
   | [] -> main_page
   | ["atom.xml"] -> atom_feed
   | [x] when permalink_exists x -> Hashtbl.find ent_bodies x
   | x ->  not_found x

  let tag = function
   | [lt1] -> (try Hashtbl.find lt1_bodies lt1 with Not_found -> not_found [lt1])
   | [lt1;lt2] -> (try Hashtbl.find lt2_bodies lt2 with Not_found -> not_found [lt2])
   
end


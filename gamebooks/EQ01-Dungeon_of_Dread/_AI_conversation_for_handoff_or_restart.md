can you rename these files by just offetting \+1. So "page (1).jpeg"  changes to "page\_2.jpeg", and onward through all files.

Let me first see what files are in the current directory.

**Glob**pattern: "\*.jpeg"Found 101 files  
**Glob**pattern: "\*.jpg"No files found  
Let me see the full count of files.

**Bash** Count total files in directory

IN

ls "c:/Users/jeff/Documents/git/repo/gamebooks/EQ01-Dungeon\_of\_Dread/jpg\_pages\_of\_book/" | wc \-l

OUT

152

**Bash** Show first and last files

IN

ls "c:/Users/jeff/Documents/git/repo/gamebooks/EQ01-Dungeon\_of\_Dread/jpg\_pages\_of\_book/" | head \-5 && echo "---" && ls "c:/Users/jeff/Documents/git/repo/gamebooks/EQ01-Dungeon\_of\_Dread/jpg\_pages\_of\_book/" | tail \-5

OUT

page (1).jpeg  
page (10).jpeg  
page (100).jpeg  
page (101).jpeg  
page (102).jpeg  
\---  
page (95).jpeg  
page (96).jpeg  
page (97).jpeg  
page (98).jpeg

page (99).jpeg

*   
*   
*   
* 

There are 152 files (`page (1).jpeg` through `page (152).jpeg`). I'll rename them all with \+1 offset: `page (1).jpeg` → `page_2.jpeg`, etc.

**Bash** Rename all page (N).jpeg to page\_N+1.jpeg

IN

cd "c:/Users/jeff/Documents/git/repo/gamebooks/EQ01-Dungeon\_of\_Dread/jpg\_pages\_of\_book" && for i in $(seq 1 152); do mv "page ($i).jpeg" "page\_$((i+1)).jpeg"; done && echo "Done. Renamed files:" && ls page\_\*.jpeg | head \-5 && echo "..." && ls page\_\*.jpeg | tail \-5 && echo "Total: $(ls page\_\*.jpeg | wc \-l)"

OUT

Done. Renamed files:  
page\_10.jpeg  
page\_100.jpeg  
page\_101.jpeg  
page\_102.jpeg  
page\_103.jpeg  
...  
page\_95.jpeg  
page\_96.jpeg  
page\_97.jpeg  
page\_98.jpeg  
page\_99.jpeg

Total: 152

All 152 files renamed successfully:

* `page (1).jpeg` → `page_2.jpeg`  
* `page (2).jpeg` → `page_3.jpeg`  
* ...  
* `page (152).jpeg` → `page_153.jpeg`

The format changed from `page (N).jpeg` to `page_N+1.jpeg` — spaces and parentheses replaced with underscores, and every number offset by \+1.

Are you able to see that file page\_2.jpeg contains text of a book that is "2" in the upper left corner? And file page\_3.jpeg has "3" in the upper right corner. These are pages of a book that have been convered (not by me) to a low dpi pdf, and I converted them to high dpi 450\. I just want the page numbers to match the file names.  Let me know if you can see that. You will run into some pages such as page\_5.jpeg that are just illustrations and do Not have a page number in their corner. I've got to think through how to handle that naming wise that keeps the files in order as they are, but adjusts the title to incude something like "\_illustration\_between\_pages\_4-5". Sequence of pages is vital, and number in filename to match actual page is vital. I thought maybe illustrations could go in a subfolder, but perhaps you have much better suggestions for all of this \- if so let me know.

Let me look at a few of the files to confirm I can read the page numbers.

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_2.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_3.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_5.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_4.jpeg

*   
*   
*   
* 

Yes, I can see everything clearly:

* **page\_2.jpeg** — "2" in upper left, text starting with "You have stopped for the night in a strange forest..."  
* **page\_3.jpeg** — "3" in upper right, continues with the halfling's dialogue  
* **page\_4.jpeg** — "4" in upper left, Laurus tells his tale about Kalman  
* **page\_5.jpeg** — Full-page illustration (warrior and halfling by moonlight), **no page number**

So the system works — I can read page numbers and distinguish illustrations from text pages.

---

Here's my suggestion for naming. I'd recommend **keeping everything in one folder** (not a subfolder) to preserve the visual browsing sequence, and using this scheme:

page\_002.jpeg          ← actual page 2  
page\_003.jpeg          ← actual page 3  
page\_004.jpeg          ← actual page 4  
page\_004a\_illus.jpeg   ← illustration between pages 4 and 5  
page\_005.jpeg          ← actual page 5

**Why this works well:**

1. **Zero-padded numbers** (3 digits) — guarantees correct alphabetical sort order up to page 999  
2. **The `a` suffix** — slots illustrations exactly after the preceding text page, before the next one. If there are multiple illustrations in a row, you get `004a`, `004b`, etc.  
3. **One folder** — you can browse/scroll through the entire book in order. A subfolder would break that flow and make it harder to know where illustrations belong in the sequence  
4. **Page numbers match** — `page_005.jpeg` actually contains page 5  
5. **`_illus` tag** — makes it instantly clear which files are illustrations vs. text, and is easy to filter with a glob (`*_illus*`)

Want me to go ahead with this approach? I'd scan through all 152 files, read each one, identify the page number (or flag it as an illustration), and rename accordingly. It'll take a bit since I need to visually inspect each image, but I can parallelize the reads to speed it up.

Yes let's try your approach

1.   
2.   
3. 

**Update Todos**

* Scan all 152 images to identify page numbers vs illustrations  
* Build rename mapping (page number or illustration designation)  
* Rename all files with zero-padded names

I already know pages 2-5. Let me scan the rest. I'll read them in parallel batches.

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_6.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_7.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_8.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_9.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_10.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_11.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_12.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_13.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_14.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_15.jpeg  
Good \- so far:

* page\_2→p2, page\_3→p3, page\_4→p4, **page\_5→illus**, page\_6→p5, page\_7→p6, page\_8→p7, page\_9→p8, page\_10→p9, page\_11→p10, page\_12→p11, page\_13→p12, **page\_14→illus**, page\_15→p13

Continuing through the book.

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_16.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_17.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_18.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_19.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_20.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_21.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_22.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_23.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_24.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_25.jpeg  
Tracking: page\_16→p14, page\_17→p15, page\_18→p16, page\_19→p17, page\_20→p18, **page\_21→illus** (giant ant), page\_22→p19, page\_23→p20, page\_24→p21, page\_25→p22. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_26.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_27.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_28.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_29.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_30.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_31.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_32.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_33.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_34.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_35.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
*   
* 

page\_26→p23, **page\_27→illus** (baboon), page\_28→p24, page\_29→p25, page\_30→p26, page\_31→p27, page\_32→p28, page\_33→p29, **page\_34→illus** (giant toad), page\_35→p30. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_36.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_37.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_38.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_39.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_40.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_41.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_42.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_43.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_44.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_45.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
*   
* 

page\_36→p31, page\_37→p32, page\_38→p33, **page\_39→illus** (spirit/wasp), page\_40→p34, page\_41→p35, page\_42→p36, page\_43→p37, page\_44→p38, page\_45→p39. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_46.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_47.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_48.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_49.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_50.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_51.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_52.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_53.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_54.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_55.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
*   
* 

page\_46→p40, page\_47→p41, page\_48→p42, page\_49→p43, **page\_50→illus** (bat creature), page\_51→p44, page\_52→p45, page\_53→p46, page\_54→p47, page\_55→p48. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_56.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_57.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_58.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_59.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_60.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_61.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_62.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_63.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_64.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_65.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
*   
* 

page\_56→p49, **page\_57→illus** (toad fight), page\_58→p50, page\_59→p51, page\_60→p52, page\_61→p53, page\_62→p54, page\_63→p55, page\_64→p56, page\_65→p57. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_66.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_67.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_68.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_69.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_70.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_71.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_72.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_73.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_74.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_75.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
* 

**page\_66→illus** (troll), page\_67→p58, page\_68→p59, page\_69→p60, page\_70→p61, **page\_71→illus** (spider), page\_72→p62, page\_73→p63, page\_74→p64, page\_75→p65. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_76.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_77.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_78.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_79.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_80.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_81.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_82.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_83.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_84.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_85.jpeg

*   
*   
*   
*   
*   
*   
*   
* 

**page\_76→illus** (water weird), page\_77→p66, page\_78→p67, page\_79→p68, page\_80→p69, page\_81→p70, page\_82→p71, page\_83→p72, page\_84→p73, page\_85→p74. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_86.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_87.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_88.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_89.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_90.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_91.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_92.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_93.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_94.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_95.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
*   
* 

page\_86→p75, **page\_87→illus** (stream/footprints), page\_88→p76, page\_89→p77, page\_90→p78, page\_91→p79, **page\_92→illus** (blink dogs), page\_93→p80, page\_94→p81, page\_95→p82. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_96.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_97.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_98.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_99.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_100.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_101.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_102.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_103.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_104.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_105.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
* 

page\_96→p83, **page\_97→illus** (green slime), page\_98→p84, page\_99→p85, page\_100→p86, page\_101→p87, page\_102→p88, page\_103→p89, page\_104→p90, **page\_105→illus** (Laurus with shield). Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_106.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_107.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_108.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_109.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_110.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_111.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_112.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_113.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_114.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_115.jpeg

*   
*   
*   
*   
*   
* 

page\_106→p91, page\_107→p92, page\_108→p93, page\_109→p94, page\_110→p95, **page\_111→illus** (ceiling collapse), page\_112→p96, page\_113→p97, page\_114→p98, page\_115→p99. Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_116.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_117.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_118.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_119.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_120.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_121.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_122.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_123.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_124.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_125.jpeg

*   
*   
*   
*   
*   
*   
*   
*   
* 

**page\_116→illus** (gargoyle), page\_117→p100, page\_118→p101, page\_119→p102, page\_120→p103, **page\_121→illus** (blink dogs), page\_122→p104, page\_123→p105, page\_124→p106, **page\_125→illus** (black pudding). Continuing...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_126.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_127.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_128.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_129.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_130.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_131.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_132.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_133.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_134.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_135.jpeg

*   
* 

page\_126→p107, page\_127→p108, page\_128→p109, **page\_129→illus** (statues/bars), page\_130→p110, page\_131→p111, **page\_132→illus** (basilisk), page\_133→p112, page\_134→p113, page\_135→p114. Continuing with the last stretch...

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_136.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_137.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_138.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_139.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_140.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_141.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_142.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_143.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_144.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_145.jpeg

*   
*   
*   
*   
*   
*   
*   
* 

page\_136→p115, **page\_137→illus** (Kalman wizard), page\_138→p116, page\_139→p117, page\_140→p118, page\_141→p119, **page\_142→illus** (Kalman fight), page\_143→p120, page\_144→p121, **page\_145→illus** (cockatrice). Final batch\!

**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_146.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_147.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_148.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_149.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_150.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_151.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_152.jpeg  
**Read** c:\\Users\\jeff\\Documents\\git\\repo\\gamebooks\\EQ01-Dungeon\_of\_Dread\\jpg\_pages\_of\_book\\page\_153.jpeg  
Scan complete\! All 152 files identified. Last batch: page\_146→p122, page\_147→p123, page\_148→p124, page\_149→p125, page\_150→p126, **page\_151→illus** (final victory), page\_152→p127, page\_153→p128.

Now let me build and execute the rename mapping. I need a two-step rename to avoid collisions (some old 3-digit names overlap with new ones).

**Update Todos**

* ~~Scan all 152 images to identify page numbers vs illustrations~~  
* ~~Build rename mapping (page number or illustration designation)~~  
* Rename all files with zero-padded names (two-step to avoid collisions)

You've hit your limit · resets 12am (America/Chicago)


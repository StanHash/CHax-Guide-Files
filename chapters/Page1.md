> ??? How does one do *ASM* hacking in C? Aren't those two different languages?

Well yes and no because while yes indeed those are two different languages that aren't source-compatible, ***C translates to ASM*** and that's the important bit.

This guide is all about revolutionizing hacking, smearing my knowledge all over your face and making Cam proud.

More seriously, in this guide we'll go over the following:

- How to make both binary (object files) & verbose assembly from C files **using makefiles** (I didn't lie when I said we were making Cam proud)
- How to link your binary (again, object files) to the game
- How to link *the game* to your C (making headers, linking to pseudo-libraries and/or abusing EA definitions)
- How to mix ASM & C for complex hooks & hacks
- More Makefile shenanigans

**This guide is _not_ about teaching C**. I'm fairly certain that the rest of the internet has that covered. You can even learn it on Youtube it's crazy. *Who would even think of making video tutorials for programming in C* (totally not me 6 years ago. Nope. No sir). (If you really don't know where to start, I have listed of bunch of potentially interesting links in the "Resources" section at the very bottom of this document, most of which I found by [searching for "C Tutorial" on DuckDuckGo](https://lmddgtfy.net/?q=C%20Tutorial))

# Getting Started

## Quick introduction to object files

You know what an elf is? Not the little guys, no, I meant the file format. If you do, you either are an experienced computer scientist and you *might* not need to read any of this, or you read my [lyn thread](http://feuniverse.us/t/ea-asm-tool-lyn-elf2ea-if-you-will/2986?u=stanh) and got confused because I can't explain shit.

Anyway, elf ([Executable Linkable Format](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)) is a format and since I'm bad I refer files that follow that format as "an elf" or even worse, "elves".

ELF is an **object file format**, and it's the one we're going to use. It's a way of describing **object files**, which are, to put it in a *very* simple way, files containing annotated data. The data part is easy to explain: it's mostly asm (in binary form), and sometimes data such as string literals or just anything really. The "annotations" are things like *symbols* (what is called what and where it is), *relocations* (where references to outside stuff are), sometimes *debug information*, fascinating stuff really.

If you were ASM Hacking the way that was taught by most active hackers today (using an utility script called something like "Assemble ARM.bat"), you already indirectly messed with object files. What that script does is call the assembler (`as`) which *generates an object file*, and then call an utility (`objcopy`) to extract the binary part from it (ignoring all that potentially useful annotation stuff, a shame really).

This worked well for assembly: We had absolute control on the layout of the binary file, so we could make sure that we were able to reference the contents of the binary relative to the beginning/end of it. For example, when we needed to call the first (and often only) routine contained in the file, we just called the address where we inserted that file.

But if we want to start to mess with higher level languages, we can't have that control anymore, so we will have to make use of means to automatically know where things are. Those means being brought to us through those object files.

*Note: Using object files isn't restricted to C hacking, you can also make use of them with regular ASM, as some hackers do.*

## (Re)Installing devkitPro/devkitARM

If you have "ASM Hacked" before, then you probably have *some* kind of installation, maybe you have the full devkitPro install ready and don't need to do a thing, *but* maybe you decided for whatever reason that Kirb's ASM Hacker's Begginner Pack thing was an awesome idea and grabbed that. If you did that, then my dude you need to get some real tools. (for the record: I don't think it was that bad of an idea, it just won't do for what we're doing now).

### Windows

**If you already installed the thing** (or think you did), go to the install folder and run `DevkitProUpdater-someversion.exe`, and make sure you *don't* have the option to install/update "Minimal System" (aka msys) & "DevkitARM". If you do, install those. You shouldn't have to do anything more, except maybe making sure you have the `DEVKITPRO` & `DEVKITARM` env variables set, and `%DEVKITPRO%/msys/bin` in your `PATH`.

[Download devkitPro releases here](https://github.com/devkitPro/installer/releases).

***NOTE: The following instructions may be outdated.*** (because new devkitPro is new)

Take the latest `.exe` installer.

Download it.

Run it.

When you get to the "Choose Components" screen, select *at least* "Minimal System" (aka msys) & "DevkitARM" (you can install other stuff if you feel like it but you don't need it here).

If it asks you to set environment variables (`DEVKITPRO` & `DEVKITARM`), do that.

If it asks you to add `%DEVKITPRO%/msys/bin` to path, do that.

If you don't know if you have the environnement variables set, then (this is for Windows 7, adapt if you need to) Computer -> Properties -> Advanced System Settings -> Environment Variables and check, set them manually if you need to (be careful there).

Now you can code your own gba games if you feel like doing that.

### Linux/Other unix (including OSX)

Using `devkitARMupdate.pl` is apparently outdated. [See here for the new official instructions and downloads](https://github.com/devkitPro/pacman/releases).

## Coding

Let's start simple:

```
int range_sum(const int* begin, const int* end) {
	int result = 0;
	
	while (begin != end)
		result = result + *begin++;
	
	return result;
}
```

(I'm sorry but as a C++ guy I need my daily dose of iterators).

This function sums together a range of values (from begin to end, excluding end) and returns the result. Nothing *too* crazy (hopefully).

Make a new folder somewhere and put that as a `.c` file in it (try not to go too crazy with the name, something like `test.c` will suffice). Make sure said folder is (mostly) empty, we'll be putting a bit more stuff in it later.

Now all we have to do is compile that, link it somehow to a FE8 ROM and call it the new crazy battle animation system that revolutionizes hacking?

No.

I think what we'll do first is see how this translates to ASM.

## Compiling

Compile with the following command:

```sh
PATH=${DEVKITARM}/bin:${PATH} && arm-none-eabi-gcc -mcpu=arm7tdmi -mthumb -mthumb-interwork -Wall -Os -mtune=arm7tdmi -fomit-frame-pointer -ffast-math -S <myfile>.c -o <myfile>.asm -fverbose-asm
```

Actually let's not. That would be messy and ugly. Instead let's keep our promise of making Cam proud and ***use Makefiles***.

DevkitARM comes bundled with a bunch of useful makefiles to include in ours (in addition to actual templates for making fully custom ROMs but we aren't here for that), so we will gladly borrow one of them (`$(DEVKITARM)/base_tools`) and include it in ours. It defines all the locations of the DevkitARM developement tools, including the one we're using (`gcc`), so we don't have to do it ourselves.

Here's a Makefile:

```makefile
.SUFFIXES:
.PHONY:

# making sure devkitARM exists and is set up
ifeq ($(strip $(DEVKITARM)),)
	$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

# including devkitARM tool definitions
include $(DEVKITARM)/base_tools

# setting up compilation flags
ARCH   := -mcpu=arm7tdmi -mthumb -mthumb-interwork
CFLAGS := $(ARCH) -Wall -Os -mtune=arm7tdmi -fomit-frame-pointer -ffast-math

# C to ASM rule
%.asm: %.c
	$(CC) $(CFLAGS) -S $< -o $@ -fverbose-asm $(ERROR_FILTER)

# C to OBJ rule
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@ $(ERROR_FILTER)
```

**Important Note**: the characters before the `$(CC)` stuff (the recipes) are *not* a bunch of spaces, but rather *tab characters* ([on your keyboard it's probably on the far left over the caps lock key](https://en.wikipedia.org/wiki/Tab_key)). If when copy-pasting you get spaces instead of tabs, replace them. This also applies to other snippets of makefiles I'll give you later.

What's great with makefiles is that it's really good at letting us define how to *make* certain type of things. For example, here I defined a **rule** for making `.asm` files from `.c` files, and another for making `.o` files from `.c` files.

It isn't really "complete" yet (see the "Advanced Makefile Shenanigans" section for more, well, *advanced* stuff), but it will do for now. And for now just assume that it works.

Anyway, in the folder your `.c` file is in, make a new file and call it `Makefile` and put all that "code" in it. **Make sure the file doesn't have any extention, that's pretty important**.

Now to run the thing.

### Windows

**Again, make sure you have `DEVKITPRO/msys/bin` in your `PATH` variable!** a quick way of checking that is by opening the command line (dw that won't be the last time) and type `echo %PATH%`.

Anyway, in explorer, Shift+Right Click on the *folder* your files are in, and select "Open command window here" (easier than to open `cmd` and manually `cd` to it).

In the command window, simply type `make <myfile>.asm`, where `<myfile>` is the name of your `.c` file, without the `.c`.

It should output something like `arm-none-eabi-gcc -mcpu=arm7tdmi -mthumb -mthumb-interwork -Wall -Os -mtune=arm7tdmi -fomit-frame-pointer -ffast-math -S <myfile>.c -o <myfile>.asm -fverbose-asm (...)`, and be done. Then you should have a new `<myfile>.asm` file. yay!

To build an object file instead of an asm file, type `make <myfile>.o` instead.

### Linux/other unix (I'll refer to that as "Lunix" from now on)

Open terminal, goto folder, type `make <myfile>.asm` (where `<myfile>` is the name of your `.c` file, without the `.c`) or `make <myfile>.o`. Same as for Windows, expect you don't need no `msys` since you already have the whole unix thing natively.

Praise Lunix.

## Quick Analysis of the generated ASM

Let's open `<myfile>.asm`. Woah what a mess, there's *a lot* of useless junk. I have like 45 lines of just it listing me the compiler options that were enabled. Ugh, but let's ignore all that and get to the core thing.

If I ignore all the comments (everything that starts with `@`), and set aside assembler directives (everything that starts with `.` except the `.L`s), I get this:

```arm
range_sum:
	movs  r3, r0
	movs  r0, #0
.L2:
	cmp   r1, r3
	bne   .L3
	
	bx    lr
.L3:
	ldmia r3!, {r2}
	adds  r0, r0, r2
	b     .L2
```

(I say "I" because you may get a slightly different output, since you may not be using the same version of `gcc` as I do, and the output may differ)

Hay! This looks like asm! Pretty well optimized asm at that. In fact you may have noticed it in the `CFLAGS` Makefile variable that I set the `-Os` `gcc` option ("optimize for size"), so the generated asm should be fairly optimally small.

Of course if you don't like `-Os`, you can also use other options (such as `-O2`/`-O3`). I suggest you read the [`gcc` program option summary](https://gcc.gnu.org/onlinedocs/gcc/Option-Summary.html) for more *options* (haha get it?).

Anyway, the generated asm looks like it does what the C function we wrote before also does. Neat.

If you look more closely in your generated file, you'll find that the generated asm is actually full of comments that directly reference the original code. That's even neater, as we get this:

```arm
range_sum:
	movs  r3, r0

@ <myfile>.c:2: int result = 0;
	movs  r0, #0

.L2:
@ <myfile>.c:4: while (begin != end)
	cmp   r1, r3
	bne   .L3

@ <myfile>.c:8: }
	bx    lr

.L3:
@ <myfile>.c:5: result = result + *begin++;
	ldmia r3!, {r2}
	adds  r0, r0, r2
	b     .L2
```

Interesting stuff, and it does match! I'm not here to overananalyse this output, but rather to teach you how to get it, and let you teach yourself what C translates to what ASM.

## Basic Linking

Ok so that's the tricky part. Before this, we were kinda doing our thing in our corner and messing around with tools. But *now* it is time to jump back into the fantastic mess of a world that is ROM Hacking.

As far as I know, there's isn't a lot of ways to properly link an object into a ROM, but let's try to list them anyway:

- By dumping the binary and inserting it directly (the good old "Assemble ARM.bat" method I already went on, again, no way of knowing how the binary is layed out, so pretty limited). This method has the advantage over the other two methods of being extremely simple (as we'll see when we get to it).

- By Setting up complex `ld` (or `gold`?) linker scripts that basically build the ROM from split parts of the original and your own hooks and things, inserting everything else in the "free" space after the end of the ROM (offset `0x1000000`+). I don't have much knowledge about that method, but it sounds not really practical, as you need to manually split the base ROM (which can be a pain, since for each split you need a separate file, and since you need to be able to put hooks all over the place, there's a lot to split).

  - This method will probably be a lot more viable once the [`FE8 Decompilation Project`](https://github.com/FireEmblemUniverse/fireemblem8u) comes to the point where everything is relocatable, as hooking will only really require to edit a file or two.

- Using [Event Assembler](http://feuniverse.us/t/event-assembler/1749?u=stanh) & [`lyn`](http://feuniverse.us/t/ea-asm-tool-lyn-elf2ea-if-you-will/2986?u=stanh). Event Assembler has already proven itself as a [powerful yet accessible tool for ROM Hacking](https://tutorial.feuniverse.us/), and `lyn` is the interface EA has to object files. (It's probably obvious that, as both the developer of `lyn` and one of the maintainers of EA I *might* be *just a bit* biased towards this method lol).

### By dumping the binary

It's a very bad idea but since I'm so nice here's a way of doing it anyway:

```makefile
# OBJ to DMP rule
%.dmp: %.o
	$(OBJCOPY) -S $< -O binary $@
```

Add that to the end of your Makefile, and then all you need to do is `make <myfile>.dmp`, and then you can insert this wherever.

It's simple to execute, at least it has that going for it.

(It also allowed me to subtly show you that you can chain rules, since here it has to do file.c => file.o => file.dmp, and can do all that in one `make` call)

Note that the sample code I gave you above *does* work with this method, since the generated ASM is the first (and only) thing in the binary.

### By making absurdly complex linker scripts

gib example thank

### By using Event Assembler & `lyn`

NOTE: From now on, I'll be assuming you are hacking FE8, since for testing I'll be messing with event slots (because those are just the best thing ever). The actual addresses will be for FE8U, so you'll have to find it yourself for FE8J (or FE8E lol).

Ok so, to put it simply, `lyn` takes an object file and makes EA code from it.

Let's take the the object file from before (`<myfile>.o`, remember?).

```sh
$ ./lyn <myfile>.o
```

We get this:

```
PUSH
ORG (CURRENTOFFSET+$1); range_sum:
POP
SHORT $0003 $2000 $4299 $D100 $4770 $CB04 $1880 $E7F9
```

What is that? Well, we see `range_sum`, which is interesting, since it's the name of our function... But it's defined at `CURRENTOFFSET+$1`... `+1`? Well that's because of the **thumb bit**. Indeed since our function was written in thumb, the **symbol** that refers to it also holds the thumb bit (this also means that we don't have to add it when refering to the symbol elsewhere, which can be confusing since that is what we used to do with binary dumping).

So the symbol (label) to our function exists within EA? That's already better than what we had with the dump method, where only the binary was left.

Speaking of binary, what's those numbers? Well everyone probably guessed it's the actual assembled assembly. You can check: each short correspond to an opcode (Uninteresting Note: instead of using `add r3, r0, #0` to encode `mov r3, r0`, which is what `as` does, `gcc` uses `lsl r3, r0, #0`. Funky stuff)

Let's test our thing! To do that we'll simply use the context of an `ASMC` event since that's easy to write. But first we need an `ASMC`-able function. Let's add that to the end of our `.c` file.

```
static int* const eventSlot = (int* const) (0x030004B8);

void test_asmc() {
	eventSlot[0xC] = range_sum(&eventSlot[1], &eventSlot[5]);
}
```

This will call `range_sum` for the values in Event Slot 1 to 5 (5 excluded, so \[Slot1\] + \[Slot2\] + \[Slot3\] + \[Slot4\]), and store the result in Event Slot C. (This is FE8U btw).

We'll use these test events:

```
	SVAL 1 1
	SVAL 2 2
	SVAL 3 3
	SVAL 4 4
	ASMC test_asmc   // call asmc
	SADD 0x0C3       // r3 = sC + s0
	GIVEITEMTOMAIN 0 // give mone
```

TL;DR we should be getting 1 + 2 + 3 + 4 = 10 gold at the end of it.

Anyway, here's the lyn output:

```
PUSH
ORG (CURRENTOFFSET+$1); range_sum:
ORG (CURRENTOFFSET+$10); test_asmc:
POP
SHORT $0003 $2000 $4299 $D100 $4770 $CB04 $1880 $E7F9 $B510 $4904 $4804 $F7FF $FFF3 $4B04 $6018 $BC10 $BC01 $4700
BYTE $CC $04 $00 $03 $BC $04 $00 $03 $E8 $04 $00 $03
```

Note that both functions have corresponding symbols, the usefulness of having "proper" linking is already showing itself.

Anyway, put the test event somewhere in a chapter (with easy access, because testing needs to be easy), put the lyn output somewhere outside of chapter events, assemble & run to see the result.

Yay! It worked! Or at least I'll assume it did for you, since it did for me. I indeed got 10 gold from the event.

So that's it I guess! You made a C hack. From now on, I'll be going over more isolated topics, which will cover some more advanced parts & tricks that can be useful when hacking in C.

## `lyn` in the makefile

I'm a bit less eager about this one than the other ones, since this one requires a bit more setup. Indeed since `lyn` is probably *not* in your path, you either have to put lyn in one of the folders in your path (I'd recommend against that personally), directly reference lyn from the full path to the binary (could be done through a Make variable but still, I don't really like it that much), or add a folder with lyn in it to your path *from the makefile* (so the modified path is only in effect during make invocation).

So, here's my way: in your makefile, put the following somewhere before the rules (say, after `include $(DEVKITARM)/base_tools`):

```
# adding local binaries to path
PATH := $(abspath .)/Tools:$(PATH)
```

Then, in the folder where the makefile is in, make a subfolder called `Tools`, and put the `lyn` binary in it (and make sure it's called `lyn` or `lyn.exe` (depending on your system)).

Now for the actual rule, add this at the end of the makefile:

```
# OBJ to EVENT rule
%.lyn.event: %.o
	lyn $< > $@
```

Now you can `make <myfile>.lyn.event`, and you'll get that sweet lyn output in, you guessed it, `<myfile>.lyn.event`.

Note: I'm choosing to generate files under the "double" extention `.lyn.event`, so that when it will come for us to write a `clean` rule, we will not accidentally remove actual hand-written event files.

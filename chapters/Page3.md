# Advanced Makefile shenanigans

Ok so here we are going to be messing with the Makefile a bit. To be clear about the state of it *before* this part, Here's what it should look like (that's assuming you did everything I told you you could with the makefile):

```
.SUFFIXES:
.PHONY:

# making sure devkitARM exists and is set up
ifeq ($(strip $(DEVKITARM)),)
	$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

# including devkitARM tool definitions
include $(DEVKITARM)/base_tools

# adding local binaries to path
PATH := $(abspath .)/bin:$(PATH)

# setting up compilation flags
ARCH   := -mcpu=arm7tdmi -mthumb -mthumb-interwork
CFLAGS := $(ARCH) -Wall -Os -mtune=arm7tdmi -fomit-frame-pointer -ffast-math

# lyn library object
LYNLIB := fe8u.o

# C to ASM rule
%.asm: %.c
	@echo "$(notdir $<) => $(notdir $@)"
	@$(CC) $(CFLAGS) -S $< -o $@ -fverbose-asm $(ERROR_FILTER)

# C to OBJ rule
%.o: %.c
	@echo "$(notdir $<) => $(notdir $@)"
	@$(CC) $(CFLAGS) -c $< -o $@ $(ERROR_FILTER)

# ASM to OBJ rule
%.o: %.s
	@echo "$(notdir $<) => $(notdir $@)"
	@$(AS) $(ARCH) $< -o $@ $(ERROR_FILTER)

# OBJ to DMP rule
%.dmp: %.o
	@echo "$(notdir $<) => $(notdir $@)"
	@$(OBJCOPY) -S $< -O binary $@

# OBJ to EVENT rule
%.lyn.event: %.o $(LYNLIB)
	@echo "$(notdir $<) => $(notdir $@)"
	@lyn $< $(LYNLIB) > $@
```

Ok that's clear now. We can proceed.

## Reviewing the Makefile

Before going further, I think this is where I need to *explain* to you *wtf is happening?* (in this particular Makefile that is)

First, [here's a link to the Make Manual TOC](https://www.gnu.org/software/make/manual/html_node/index.html). Everything you need to know is there. I'll assume you're reading *at least* the [Intro](https://www.gnu.org/software/make/manual/html_node/Introduction.html) of the whole thing, since this is where you'll learn the very basics.

Let's go line-by-line, and I'll be linking you to the Make manual all over the place so that you can learn more.

```
.SUFFIXES:
.PHONY:
```

Those basically reset some [special built-in "targets"](https://www.gnu.org/software/make/manual/html_node/Special-Targets.html). `.SUFFIXES` is the list of "suffixes" that are valid in the context of ["suffix rules"](https://www.gnu.org/software/make/manual/html_node/Suffix-Rules.html) that we don't use (we use [pattern rules](https://www.gnu.org/software/make/manual/html_node/Pattern-Rules.html) instead), and is best kept empty. `.PHONY` decribes the list of ["phony targets"](https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html), which are, to keep it simple, targets that don't refer to a file. We'll get to that soon-ish.

```
# making sure devkitARM exists and is set up
ifeq ($(strip $(DEVKITARM)),)
	$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

# including devkitARM tool definitions
include $(DEVKITARM)/base_tools
```

This part, as the [comments](https://www.gnu.org/software/make/manual/html_node/Makefile-Contents.html) suggest, is responsible for:

- making sure devkitARM is set up (using [conditionals](https://www.gnu.org/software/make/manual/html_node/Conditional-Example.html) and [raising an error](https://www.gnu.org/software/make/manual/html_node/Make-Control-Functions.html) when it isn't)
- [including](https://www.gnu.org/software/make/manual/html_node/Include.html) the devkitARM tool-defining makefile (it (re)defines [variables](https://www.gnu.org/software/make/manual/html_node/Using-Variables.html) such as `CC`, `CXX`, `OBJCOPY`, ...)

```
# adding local binaries to path
PATH := $(abspath .)/bin:$(PATH)
```

Adds our local binary directory (`./bin`, but its [absolute path](https://www.gnu.org/software/make/manual/html_node/File-Name-Functions.html)) to the [PATH](https://en.wikipedia.org/wiki/PATH_\(variable\)) [variable](https://www.gnu.org/software/make/manual/html_node/Using-Variables.html). We added this when we first used `lyn` in this, remember? Yeah because `lyn` should be in that `./bin` folder.

```
# setting up compilation flags
ARCH   := -mcpu=arm7tdmi -mthumb -mthumb-interwork
CFLAGS := $(ARCH) -Wall -Os -mtune=arm7tdmi -fomit-frame-pointer -ffast-math
```

Sets [variables](https://www.gnu.org/software/make/manual/html_node/Using-Variables.html) that are really just [lists of options for GCC](https://gcc.gnu.org/onlinedocs/gcc/Option-Summary.html) & [AS](https://sourceware.org/binutils/docs/as/Invoking.html).

```
# lyn library object
LYNLIB := fe8u.o
```

The "library" object file for linking through `lyn`. See the section about that for details.

After that, we just have a bunch of [rules](https://www.gnu.org/software/make/manual/html_node/Rules.html). All [pattern rules](https://www.gnu.org/software/make/manual/html_node/Pattern-Rules.html) even. Since they all follow the same repetitive format, we are going to look at the first one only.

```
# C to ASM rule
%.asm: %.c
	@echo "$(notdir $<) => $(notdir $@)"
	@$(CC) $(CFLAGS) -S $< -o $@ -fverbose-asm $(ERROR_FILTER)
```

This is the [pattern rule](https://www.gnu.org/software/make/manual/html_node/Pattern-Rules.html) that describes how to make `.asm` files from `.c` files. Its recipe is fairly simple: first we [echo](https://en.wikipedia.org/wiki/Echo_\(command\)) "\[dependency\] => \[target\]". Because I felt like doing that (that way we know what's going on). Next we call "`CC`" (it's a variable that contains the name of the C compiler, which is `gcc`, and was defined in the devkitARM tool makefile thing) with `$(CFLAGS) -S $< -o $@ -fverbose-asm $(ERROR_FILTER)` for arguments.

`$(CFLAGS)` are the arguments defined before. `-S` means we want to generate *asm* (and not an object file, in which case we would have specified `-c`). `$<` sets the input. It is the [automatic variable](https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html) specifying the first prerequisite (here, the `.c` file). `-o $@` sets the output. `$@` is the [automatic variable](https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html) specifying the target name (here, the `.asm` file). `-fverbose-asm` means we want the asm to be *verbose* (lots of comments, including annotations that correspond to the `.c` source file). `$(ERROR_FILTER)` idk but the devkitARM stuff uses it so it's probably neat.

All the other pattern rules are like that.

## Listing files

A thing that can get useful eventually, is building a list of a certain type of file. What we are going to do now is make a Makefile variable called `CFILES`, and it will be a generated list of all `.c` files make can find. Here:

```
# listing C files
CFILES := $(wildcard *.c)
```

We got the list using the [wildcard function](https://www.gnu.org/software/make/manual/html_node/Wildcard-Function.html), easy. We can do the same with `SFILES` for asm (hand-written, so with the `.s` extention here) files:

```
# listing S files
SFILES := $(wildcard *.s)
```

Note that these lists are *not* built from subfolders. If you want a "recursive" wildcard, [this stackoverflow question (and the awnsers)](https://stackoverflow.com/questions/2483182/recursive-wildcards-in-gnu-make) might be interesting to you.

Now let's list *possible* files. Like the list of all the object files we can get:

```
# listing possible object files
OFILES := $(CFILES:.c=.o) $(SFILES:.s=.o)
```

Since listed elements are space-separated, this way of using [substitution references](https://www.gnu.org/software/make/manual/html_node/Substitution-Refs.html) works.

We can also make a list of asm files or lyn event files that way:

```
# listing possible generated asm files
ASMFILES := $(CFILES:.c=.asm)

# listing possible lyn event files
LYNFILES := $(OFILES:.o=.lyn.event)

# listing possible dmp files
DMPFILES := $(OFILES:.o=.dmp)
```

Ok but why are we doing this?

## "Make all" targets

Let's add in a target that we will call "objects", so that if we `make objects`, we make all the object files we can make.

```
# "make all objects" phony target
objects: $(OFILES);
```

Of course, me and my comments spoiled all the fun. It will be the first "Phony target" we will include. So we add it to the `.PHONY` list:

```
.PHONY: objects
```

We want it phony for it to not interfere with any eventual file called "objects".

Now we can `make objects` and it will make all the objects it can make! This works because the target *depends* on all the objects in the `OFILES` variable, which is the list of all objects that can be made from `c` and `s` files. Even if the `object`-making rule has no recipe, it will still resolve all its dependencies.

Also, since `objects` is the first target we define, it will be the default "goal" when we call simply `make`.

So, you guessed it, we can also add similar rules called, say, `events`, `asmgen` and `bindmps`:

```
# "make all" phony targets
objects: $(OFILES);
asmgen: $(ASMFILES);
events: $(LYNFILES);
bindmps: $(DMPFILES)
```

And add them to `.PHONY`:

```
.PHONY: objects asmgen events bindmps
```

Yay.

## "Clean" target

[This one is kind of a conventional one](https://www.gnu.org/software/make/manual/html_node/Cleanup.html), but let's be honest our folder is becomming a mess we probably want to tidy it up at some point.

Here we go:

```
# "Clean" target
clean:
	@rm -f $(OFILES) $(ASMFILES) $(LYNFILES) $(DMPFILES)
	@echo done.
```

And we add it to the `.PHONY` list:

```
.PHONY: objects asmgen events bindmps clean
```

Now, we can `make clean` to [`rm`](https://en.wikipedia.org/wiki/Rm_\(Unix\)) all the files that were generated or could have been generated by our makefile.

## Automatic C Source-Header Make Dependency Generation (Or Something)

TL;DR we want to generate, for each C File, a list of dependencies that correspond to the `#included` files.

Well I say C File, but we want dependencies for the corresponding object file, because, you know, that's what the target is.

The goal of this whole thing is to make it so that when you *only* modify some header, that the object file(s) for the including C files are still rebuilt.

There is [a number](https://www.gnu.org/software/make/manual/html_node/Automatic-Prerequisites.html) [of ways](http://make.mad-scientist.net/papers/advanced-auto-dependency-generation/) [we can](http://www.microhowto.info/howto/automatically_generate_makefile_dependencies.html) [tackle this](https://gist.github.com/maxtruxa/4b3929e118914ccef057f8a05c614b0f).

What all those methods have in common is that they call `CC` (the C Compiler, in our case `gcc`) with [some variant of the `-M` option](https://gcc.gnu.org/onlinedocs/gcc/Preprocessor-Options.html). What this option does is tell the preprocessor to generate *a makefile* defining dependencies.

For example, let's say we have a `test.c` file that `#include`s a `gbafe.h` file, which in turn includes a `gbafe_unit.h` file. We would get, from `$(CC) -M test.c`, the following:

```
test.o: test.c gbafe.h gbafe_unit.h
```

This "makefile" contains a single rule. This rule tells `make` that the `test.o` target depends on `test.c`, but also `gbafe.h` and `gbafe_unit.h`, since those are included, either directly or indirectly, by `test.c`.

Neat, but how do we get that into our main makefile... And how (and when) do we generate it? Well this is where the different methods I found differ, so what follows is my version of the whole thing.

What we are going to do is generate it *while compiling* (as a side-effect of compilation) (requiring the `-MD` or `-MMD` option), and include it *if it exists*. I think this is the simplest way we can do that, since it doesn't require us to define any extra pattern rule for "dependency makefiles" and works okay since the only case in which dependency makefiles don't exist is when the object never was built in the first place (in which case a dependency makefile isn't useful since the object would be build unconditionally).

Anyway, first lets list all the possible dependency makefiles from C files, so that we can easily include and/or clean them when we need to:

```
# listing possible dependency files
DEPFILES := $(CFILES:.c=.d)
```

(I'm choosing the `.d` extention because this seems to be the convention)

Since we're at it, we can add those to the clean rule:

```
# "Clean" target
clean:
	@rm -f $(OFILES) $(ASMFILES) $(LYNFILES) $(DMPFILES) $(DEPFILES)
	@echo done.
```

Next, we [`include`](https://www.gnu.org/software/make/manual/html_node/Include.html) them, but since those files *may not exist*, we will use `-include` (it tells make to ignore missing files, instead of raising an error). I chose to put that at the end of the main Makefile:

```
-include $(DEPFILES)
```

(Note that *make* `include` can take multiple files, which is what we want since `DEPFILES` is a list)

Next we define a variable containing the extra options we'll use for generating dependencies when generating objects from C:

```
# dependency generation flags for CC
CDEPFLAGS = -MD -MT $@ -MF $*.d
```

(Note that I used the "classic" way of defining variables. This means that, unlike variables defined with `:=`, the value of this variable will be evaluated when it's referenced (this mainly affects the `$@` & `$*` [automatic variables](https://www.gnu.org/software/make/manual/html_node/Automatic-Variables.html): they will only be expanded when needed aka in the `.c` to `.o` pattern rule))

(`-MD` means "generate dependency makefile as side-effect of compilation", `-MT $@` sets the target for the generated makefile, and `-MF $*.d` sets the output makefile file name)

Finally, we modify the `.c` to `.o` rule to make it generate the dependency makefile:

```
# C to OBJ rule
%.o: %.c
	@echo "$(notdir $<) => $(notdir $@)"
	@$(CC) $(CFLAGS) $(CDEPFLAGS) -c $< -o $@ $(ERROR_FILTER)
```

Now to test the thing. Remember this source file:

```
#include "gbafe.h"

void some_asmc() {
	eventSlot[0xC] = GetGameTime();
}
```

Well lets `make` its object. Now let's try again. I will tell you `'<whatever>.o' is up to date.`. Now let's modify `gbafe.h` and *only* `gbafe.h` (just add an extra line whatever). Now `make` again... Bingo! It's been rebuilt. Mission accomplished.

### What happens when we delete a header?

```
make: *** No rule to make target '<header>.h', needed by '<source>.o'.  Stop.
```

Ouch. Even if, in the source file, we correctly removed the reference to the header, Make still thinks it needs `<header>.h` to build the object.

That's because the dependency makefile still exists and still references the missing header... But the dependency makefile will only get updated when the object will get generated. Yet we can't generate the object because of the dependency makefile... Unless we `make clean` (which honestly isn't a very elegant solution), we're stuck.

Fortunately, GCC comes with a neat option (`-MP`) that makes use of [a neat Make feature](https://www.gnu.org/software/make/manual/html_node/Force-Targets.html) that says that if a rule with a target but without dependency or recipe exists, but the corresponding file doesn't, it considers the target as updated, and "all targets depending on this one will always have their recipe run".

So if we had the rule "`<header>.h:`", then since that file doesn't exists, everything depending on it would have been forced to be rebuilt. In other words, we would have found a way out of our initial problem. Neat.

All of this to tell you that all we need to do is add that `-MP` option to the `CDEPFLAGS` variable:

```
# dependency generation flags for CC
CDEPFLAGS = -MD -MT $@ -MF $*.d -MP
```

### But what about the `.c` to `.asm` rule?

Right. This isn't really a thing the various guides I linked you earlier went on, since it's kind of our custom thing here. But don't worry! I have a solution. A fairly simple one even.

See, [rules can have mutiple targets](https://www.gnu.org/software/make/manual/html_node/Multiple-Targets.html). When you do that, it essentially means that you're defining multiple rules each with one target.

This also means that we can have `gcc` generate rules that apply to multiple targets. See where I'm going? Yes we will tell it to generate rules for both `.o` and `.asm` files.

We can do that very simply by adding another `-MT` option to `CDEPFLAGS`:

```
# dependency generation flags for CC
CDEPFLAGS = -MD -MT $*.o -MT $*.asm -MF $*.d -MP
```

Note that I switched from using `$@` (the target name) to `$*` (the pattern match), so that we can also use `CDEPFLAGS` in the `.c` to `.asm` rule (those flags are target-independent and that's the important bit):

```
# C to ASM rule
%.asm: %.c
	@echo "$(notdir $<) => $(notdir $@)"
	@$(CC) $(CFLAGS) $(CDEPFLAGS) -S $< -o $@ -fverbose-asm $(ERROR_FILTER)
```

### There are "D" files all over the place now! How to I hide them?

Well if you *really* don't like them all that much I could help you. But it comes at a cost.

See, we could put all those `.d` files in a dedicated folder (say `.MkDeps`, the dot is there so that it gets hidden on most unix systems), this would remove them from all over the place.

But we then have an issue: what if I have `test.c` and `someFolder/test.c`? Both files would generate a `test.d` file, even if those are two different files. In our current situation it's okay, since those files would be in different folders... But if we put them in a single dedicated folder it would mess things up. So yeah, the downside of this method is that we can't have two files with the same name.

Anyway, I'll still teach you. First we are going to define a Make variable containing the directory name:

```
# defining & making dependency directory
DEPSDIR := .MkDeps
$(shell mkdir -p $(DEPSDIR) > /dev/null)
```

(To Windows users: yes this works, `msys` is there for you. Don't worry about this alien `/dev/null` stuff)

It's also making sure the directory *exists* (by forcing it to be made). Make doesn't make directories automatically (sadly, because it would be so much easier if it did).

Anyway now that we have this setup, let's modify our references to `.d` files so that they all end up in this directory:

```
# listing possible dependency files
DEPFILES := $(addprefix $(DEPSDIR)/, $(notdir $(CFILES:.c=.d)))

# dependency generation flags for CC
CDEPFLAGS = -MD -MT $*.o -MT $*.asm -MF $(DEPSDIR)/$(notdir $*).d -MP
```

(Note how I used the [`notdir` & `addprefix`](https://www.gnu.org/software/make/manual/html_node/File-Name-Functions.html) Make functions to "change" the directory the file is in)

And... that's about it. Fairly simple. Now every dependency makefiles will be generated in that directory.

Eventually when you may want to hide other generated makefiles or intermediate files you could re-purpose this directory as more general-purpose "cache" or "build" directory.

# Resources

### Directly related

- [The GitHub repository containing a sample project covering everything said here](https://github.com/StanHash/CHax-Guide-Files), including the final Makefile, example code, and *more*.
- [My C Hacking repository](https://github.com/StanHash/FE-CHAX), which contains a well-advanced "library" declaring function & structures and defining addresses for FE8U (see the "Advanced Linking" section), as well as actual applications of about everything I tried to teach here.

### C Learning Material

- [C Tutorial (cprogramming.com)](https://www.cprogramming.com/tutorial/c-tutorial.html)
- [C Programming (e-?)book (wikibooks)](https://en.wikibooks.org/wiki/C_Programming)
- [GNU C Reference Manual (for reference)](https://www.gnu.org/software/gnu-c-manual/gnu-c-manual.html)
- ["Learn C" (apparently it's interractive)](https://www.learn-c.org/)
- Some video tutorials (probably not that great, but still better than what I might have done in my youth)
  - [Some video tutorial (one big 4 hour one)](https://www.youtube.com/watch?v=-CpG3oATGIs)
  - [Some other video tutorial (that's a playlist)](https://www.youtube.com/watch?v=2NWeucMKrLI&list=PL6gx4Cwl9DGAKIXv8Yr6nhGJ9Vlcjyymq)

### Doc on the tools we used

- [GNU GCC Documentation](https://gcc.gnu.org/onlinedocs/gcc/index.html)
- [GNU Binutils AS Documentation](https://sourceware.org/binutils/docs/as/)
- [GNU Make Documentation](https://www.gnu.org/software/make/manual/html_node/index.html)

### Doc on *the game*

- [Fire Emblem Universe (aka here)](http://feuniverse.us/search)
- [The Unified FEU Docbox](https://www.dropbox.com/sh/zymc1h221nnxpm9/AAAruCnsQf574gY_Yi7s1KP0a?dl=0), which includes:
  - [*The* Teq Doq](https://www.dropbox.com/sh/zymc1h221nnxpm9/AACrgal3LFRvbDKL-5qDxF3-a/Tequila/Teq%20Doq?dl=0)
  - [Circle's Stuff](https://www.dropbox.com/sh/zymc1h221nnxpm9/AAAlT0_3pYaI0oD2LsVJI9DCa/Circles?dl=0)
  - [Colorz's Stuff](https://www.dropbox.com/sh/zymc1h221nnxpm9/AAC77X60EZgyoIhpjTddaiC5a/Crazycolorz5's%20Stuff?dl=0)
  - [Tera's Stuff](https://www.dropbox.com/sh/zymc1h221nnxpm9/AAB5bdNC0FAi1OJOk4CnoKB7a/Teraspark?dl=0)
  - [Venno's Stuff](https://www.dropbox.com/sh/zymc1h221nnxpm9/AAD8Sp6DUoN2Eh7AZN9Uk2Jma/Venno's%20things?dl=0)
  - [Zane's Stuff from when he wasn't doing FE5 yet](https://www.dropbox.com/sh/zymc1h221nnxpm9/AADEcescLH95KxKv8KrPqWT5a/Zane's%20Stuff?dl=0)
  - [jjl's Stuff](https://www.dropbox.com/sh/zymc1h221nnxpm9/AADArQAQ19cFzEEwXpnJp8z5a/jjl2357's%20notes?dl=0)
  - [Nintenlord's Doc](https://www.dropbox.com/sh/zymc1h221nnxpm9/AACbnRPkRlnuOJOAaYYngZaoa/Nintenlord/My%20notes?dl=0)
  - [Hextator's Doc (shh)](https://www.dropbox.com/sh/zymc1h221nnxpm9/AACnmgDdFEpMs4Qsx4tKMg2Va/Hextator's%20Doc?dl=0)
  - [My Stuff (including some snapshorts of my `idb`)](https://www.dropbox.com/sh/zymc1h221nnxpm9/AAA1sHR4hvxFxZYqOF3zqkG6a/Stan/_Notes?dl=0)
  - Just take the time to go through it, it isn't called the "gold mine" for no reason
- [doc.feuniverse.us (Mostly Cam's stuff right now)](https://doc.feuniverse.us/)
- [the FEU Discord (read: ask people)](http://feuniverse.us/t/feu-discord-server/1480?u=stanh)

### My stuff (gotta plug it)

- [My GitHub](https://github.com/StanHash), which includes sources for:
  - [My Older ASM Hacks](https://github.com/StanHash/FE8UASMHax)
  - [My Newer C Hacks](https://github.com/StanHash/FE-CHAX)
  - [`lyn`](https://github.com/StanHash/lyn)
  - [`pea`](https://github.com/StanHash/pea-preprocessor)
  - [`TEA`](https://github.com/StanHash/TEA)
- [My Stuff in the Unified Docbox (doesn't hurt to put it twice)](https://www.dropbox.com/sh/zymc1h221nnxpm9/AAA1sHR4hvxFxZYqOF3zqkG6a/Stan/_Notes?dl=0)
- [The `lyn` thread](http://feuniverse.us/t/ea-asm-tool-lyn-elf2ea-if-you-will/2986?u=stanh)
- [The old-ish "Stan's ASM Stuff" thread](http://feuniverse.us/t/fe8-stans-asm-stuff/2376?u=stanh)

### Other

- [Event Assembler](http://feuniverse.us/t/event-assembler/1749?u=stanh)
- [the FEU Discord (again, since it's important)](http://feuniverse.us/t/feu-discord-server/1480?u=stanh)

# The End

Thank you for reading. This is by far the most work I have ever put in a document ever (It took me like 3 days while putting 10 hours a day on it), so hopefully it will be useful to *someone*.

Of course if you find any errors or ambiguous bits, or just have suggestions for improving all of this I'm all ears.

Remember: when in doubt, `ALIGN 4`.

On that note, Have a nice day! -Stan

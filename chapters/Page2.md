# Advanced Linking (with `lyn`)

In the linking demonstration, I taught you how to link *C with the game*, aka how to make the game call C. But how do we do the opposite? How do we call the already existing parts of the game with C? How do we *link the game with C*?

I'll tell you something crazy: the game was actually *probably* written in C. I say probably but it's really almost definitely true (The ultimate confirmation for me was the presence of C file names in the prototype build of FE8).

This isn't very useful for us, except maybe for that part where it means that routines in the game probably follow C function signature conventions.

In this chapter, I'll use the simple example of the "`GetGameTime`" function (It doesn't have any "official" name, I just call it that), located in FE8U at `0x08000D28`, that returns the game time and takes no arguments. We'll assume its signature is the following:

```
int GetGameTime();
```

## Declaring pointers in the source

If you did some ASM Hacking before (you probably did), you may have done the following: you defined the address of a game routine you wanted to call, loaded that and "`bl` to `bx`"ed to it (or "`.short 0xF800`"ed to it). And you totally can do a similar thing in C too! I even kinda did that in the example when writing to event slots. Those were simple int pointers, but you can do the same thing with function pointers, look:

```
static const int(*GetGameTime)() = (int(*)()) (0x08000D29); // note the thumb bit

static int* const eventSlot = (int* const) (0x030004B8);

void some_asmc() {
	eventSlot[0xC] = GetGameTime();
}
```

I want to show you that this indeed works. Let's look at the asm (The comments are my addition, so that things were a bit more clear):

```
some_asmc:
	push {r4, lr}
	
	ldr  r3, .L2   @ =0x08000D29
	bl   .L4       @ bx r3
	
	ldr  r3, .L2+4 @ =0x030004B8+0xC*sizeof(int)
	str  r0, [r3]
	
	pop  {r4}
	pop  {r0}
	bx   r0
.L3:
	.align 2
.L2:
	.word 134221097 @ 0x08000D29
	.word 50332904  @ 0x030004B8+0xC*sizeof(int)
	.code 16
	.align 1
.L4:
	bx   r3
```

Yup, that's your good old `bl` to `bx` trick.

Ok so that works, and if you think that's enough that's fine I won't judge... Maybe. See, having things work isn't all that matters when programming. It's also about organizing things and a way that makes sense, so that when it comes the time you need to fix, port or adapt your code, you want to be in a comfortable situation when doing that.

And, lets be honest... That function pointer definition is also kinda ugly. Not only that but it's also not very portable. I didn't really speak about it up until now but it would be nice if our code could be compatible with different version of FE8, or even with FE7 or FE6 for that matter (well not that code particularly, since event slots weren't a thing at the time, but you get the point), since writing at a higher level allows us that.

## Creating a "library"

So here's the deal: we are going to decouple the *declaration* of what the game provides us (including the *signature* of functions), and the *definition* of where it is.

The *declaration* part, you probably guessed it, we are going to put that in a *header* file. Let's call it, say, `gbafe.h`. It would contain function declaration, but also maybe in time structure definitions for data from the game (like say, the [unit struct](https://github.com/StanHash/FE-CHAX/blob/master/libgbafe/gbafe/unit.h)). From that all we need to do in our source file is to `#include` it and use it.

Here's the header file containing "`GetGameTime`" and "`eventSlot`" declarations:

```
#ifndef GBAFE_H
#define GBAFE_H

extern int eventSlot[];

int GetGameTime();

#endif // GBAFE_H
```

Ok so I guess now I need to explain a bit more about symbols and how C names translate to them. See the `eventSlot` declaration? It will generate a (undefined) `eventSlot` symbol. The value of that symbol is expected to be the *address of the object it represents*.

This is why I decided to declare `eventSlot` as an array and *not* a pointer, because if I declared a pointer, It would expect as value the address of a pointer, but the address I want to give it is the address of the event slot value array (`0x030004B8`), and the data there isn't a pointer, but the value of slot 0 (which so happens to be 0 most of the time, not really a useful pointer).

Here's the C file we'll use:

```
#include "gbafe.h"

void some_asmc() {
	eventSlot[0xC] = GetGameTime();
}
```

Generated ASM:

```
some_asmc:
	push  {r4, lr}
	bl    GetGameTime
	ldr   r3, .L2
	str   r0, [r3, #48]
	pop   {r4}
	pop   {r0}
	bx    r0
.L2:
	.word eventSlot
```

Notice that the generated code only uses a standard `bl`, which may cause problems (mainly because the main game code isn't usually within `bl`-range of our inserted hacks), so how do we make it a safer `bl` to `bx`?

Note: if you are using `lyn`, it is even more important to transform `bl`s into `bl` to `bx`es, since `lyn` can't *relocate* (that's the term for when a reference in an object file (aka a *relocation*) is being resolved properly) *relative* references (such as a `bl`) to external symbols. This comes from the simple fact the `lyn` doesn't know where the object it links will be (since that's for EA to decide).

So, there's two ways we can do that: either during linking, or during compilation.

#### During linking

`lyn` comes with the `-longcalls` option, This tells `lyn` that when it finds itself in a situation where it can't properly relocate a symbol because the relocation isn't absolute (for example: when relocating a `bl`), it is allowed to add extra code (a "veneer") to "make" it absolute. Example:

- Without `-longcalls`:
  
```
PUSH
ORG (CURRENTOFFSET+$1); some_asmc:
POP
SHORT $B510
SHORT ((((GetGameTime-4-CURRENTOFFSET)>>12)&$7FF)|$F000) ((((GetGameTime-4-CURRENTOFFSET)>>1)&$7FF)|$F800)
SHORT $4B02 $6318 $BC10 $BC01 $4700
POIN eventSlot
```

- With `-longcalls`:

```
PUSH
ORG (CURRENTOFFSET+$1); some_asmc:
POP
{
PUSH
ORG (CURRENTOFFSET+$15); _LP_GetGameTime:
POP
SHORT $B510
SHORT ((((_LP_GetGameTime-4-CURRENTOFFSET)>>12)&$7FF)|$F000) ((((_LP_GetGameTime-4-CURRENTOFFSET)>>1)&$7FF)|$F800)
SHORT $4B02 $6318 $BC10 $BC01 $4700
POIN eventSlot
SHORT $4778 $46C0
WORD $E59FC000 $E12FFF1C
POIN GetGameTime
}
```

Whoah that's a lot of new stuff. In realtity that's only 16 extra bytes (2 SHORTS, 2 WORDS, 4 BYTES at the very end of the thing). But there's also a new symbol, `_LP_GetGameTime` [s]that probably shouldn't be here because it should know how to optimize it away so that's a bug for me to fix but in this particular case it's useful for getting my point accross[/s], that replaces the regular `GetGameTime`, and this time it is properly defined and it even doesn't pollute the global EA namespace since it's enclosed in curly brackets.

The extra 16 bytes at the end are a piece of asm that "transforms" the `bl` into a `bl` to `bx`. It's different to a regular `bl` to `bx` because the setup here is done *after* the `bl`.

Anyway, since the call is transformed, `lyn` could relocate the `GetGameTime` symbol if it knew where it was (we'll get to that). Even better: we aren't limited by the potential limitation of the range of the `bl` instruction (+-4MB). Mission accomplished... But I think we can be better.

#### During compilation

There's multiple ways to go on this:

- We could use a program option (`gcc` for ARM takes `-mlong-calls`), that's okay, but it would make *all* references to outside code a "long call", so there's probably a better way.

- We could also use function attributes in our header to specifiy we want to long call:
  
    ```
    int GetGameTime() __attribute__ ((long_call));
    ```
  
    That's okay right now, but then if we start adding other signatures it can get tedious really fast.
  
- We could use `#pragma long_calls`:
  
    ```
    #pragma long_calls
    
    int GetGameTime();
    
    // as many other function declaration as you want
    
    #pragma long_calls_off
    ```

Anyway in all three cases we get this ASM:

```
some_asmc:
	push  {r4, lr}
	
	ldr   r3, .L2
	bl    .L4
	
	ldr   r3, .L2+4
	str   r0, [r3, #48]
	
	pop   {r4}
	pop   {r0}
	bx    r0

.L2:
	.word GetGameTime
	.word eventSlot

.L4:
	bx    r3
```

A good old `bl` to `bx`. Wonderful. And it looks way better than what `lyn` did, which makes sense: since we tackled the problem earlier, the solution is way less "pulled by the hair" (is that something that's said in english? Shame if not).

Ok so now comes the *definition* part. I'll show you *two* ways to handling that: through a "library object" (my recommendation), and through EA (for the lazy ones).

### Definition through a "library object"

In this method, we *define* the symbols we need in an external object file: the "library object". This file and *only* this file (in theory) is game-specific, since this is the only file where we will have actuall addresses in it.

This source file will *not* be a C file, but a good old ASM file. We won't be putting any ASM in it tho, we will rather be abusing assembler directives to *generate an object file containing the symbol definitions we need*.

Here's mine:

```
.macro SET_ABS_FUNC name, value
	.global \name
	.type   \name, %function
	.set    \name, \value
.endm

.macro SET_ABS_DATA name, value
	.global \name
	.type   \name, %object
	.set    \name, \value
.endm

SET_ABS_DATA eventSlot,   (0x030004B8)

SET_ABS_FUNC GetGameTime, (0x08000D28+1)
```

Note that I'm defining through helper macros I also defined. For now it seems kinda redundant but later when we start to add dozens of extra functions and/or references to data, you'll thank me.

Anyway, I called it `fe8u.s` (I'm willingly choosing a different extention to the one for generated asm from C files, as it allows me to differentiate between generated asm and hand-written asm (gets useful when writing `clean` rules in the makefile later)).

Hey! We don't even have a rule for making object files from asm in our makefile (this probably means that I'm doing a good job), so let's remedy this. Add this to your makefile:

```
# ASM to OBJ
%.o: %.s
	@echo "$(notdir $<) => $(notdir $@)"
	@$(AS) $(ARCH) $< -o $@ $(ERROR_FILTER)
```

Now we can `make fe8u.o` (we can also `make fe8u.lyn.event`, but this will just generate a blank file, as there isn't any data nor local symbols defined in it, and `lyn` doesn't expose absolute symbols).

Ok so now what? We have a nice object file with our symbols defined in it, and a nice header with our symbols declared... but how do we use all that?

The awnser is: we need to link the object file generated from that C file with `fe8u.o`. When we do that, the symbols referenced by the C object will be sustitued by their definition from the `fe8u.o` object. To do that, we simply pass them both to `lyn`:

```
$ ./lyn <myfile>.o fe8u.o
```

It gives me this:

```
PUSH
ORG (CURRENTOFFSET+$1); some_asmc:
POP
SHORT $B510 $4B04 $F000 $F80A $4B03 $6318 $BC10 $BC01 $4700 $46C0
BYTE $29 $0D $00 $08 $B8 $04 $00 $03
SHORT $4718 $46C0
```

Sweet. We linked our objects together.

#### (Makefile) Automatically making & linking the library object

I'm going to assume we need that library object for *all* of our `lyn` links. That way we can take the rule for making `.lyn.event` files and modify it accordingly:

```
# OBJ to EVENT rule
%.lyn.event: %.o fe8u.o
	@echo "$(notdir $<) => $(notdir $@)"
	@lyn $< fe8u.o > $@
```

If you aren't familiar with makefiles: I added a second *dependency* to the pattern rule for generating `.lyn.event` from `.o` files. This means that each time you require a `.lyn.event`, it will first make sure that both the corresponing `.o` file and the `fe8u.o` file are *up to date* (aka younger than their own dependencies).

This story about makefiles & up-to-dateness will come again later when we will learn how to generate dependency definitions for our C files (that are including other files, on which the source *depends* on).

Anyway, this simple change makes sure that the library is built before building the `.lyn.event` file.

Also the `lyn` call was changed to include the library too.

You could also define a Make variable that holds the library file to link against. For example:

```
# lyn library object
LYNLIB := fe8u.o
```

And the rule becomes

```
# OBJ to EVENT rule
%.lyn.event: %.o $(LYNLIB)
	@echo "$(notdir $<) => $(notdir $@)"
	@lyn $< $(LYNLIB) > $@
```

### Definition through EA

When `lyn` can't relocated something, it doesn't fail. Instead it just writes the name of the targetted symbol in place, letting EA handle it and probably fail in its place.

But we can also take this to our advantage. If we get our object and `lyn` it, we get this:

```
PUSH
ORG (CURRENTOFFSET+$1); some_asmc:
POP
SHORT $B510 $4B04 $F000 $F80A $4B03 $6318 $BC10 $BC01 $4700 $46C0
POIN GetGameTime eventSlot
SHORT $4718 $46C0
```

Direct reference to the missing symbols can be seen. So what do we do? Well, we `#define` them!

```
#define GetGameTime "(0x08000D28+1)"
#define eventSlot   "(0x030004B8)"
```

ez. Know that since EA 11.1 (the version in which I did stuff shh that's a secret), A feature exists that allows us to do the following:

```
GetGameTime = 0x08000D28+1
eventSlot   = 0x030004B8
```

Anyway, done. Put that anywhere (if you used `#define`, it needs to be brefore the `lyn` output), and the `lyn` output *will* assemble and link correctly. Hurray!

This is obviously easier than to go through all the hassle of making another object file and linking it via a `lyn` call and all, and also way more clean that the brute way of defining const function pointers. I'm guessing most people reading this (side note: that's probably not a lot of people) will choose to use this method over the other two.

The issue I find with this method is in the hack distribution side of things. I think making the smallest (in event file size/EA computation needs), easiest to install (`#include` and be done), and less polluting (as in: polluting the EA global namespace with useless junk) hacks is a priority (coming from me and my MSG Helpers & Ultra-Flexible Heroes Movement Hacks, this would probably sound somewhat inconsistent to some people).

~~It also would suck if one day you decide to not use EA anymore~~.

TL;DR: I think the less EA does, and the more processing you can have done before the "EA" phase, the better it is.

# Integrating ASM & C

Ok, so you already know how to call C from Events (`ASMC`, see our first example) and probably have an idea of how to call C with EA `Extentions/Hack Installation.txt` Macros (`jumpToHack`, `callHack_rx`, ...), since it's basically the same in a different context.

Here we are going to see how to integrate your C code & regular "raw" ASM. This will be probably most useful when setting up more elaborate hooks and you need to setup some very precise ASM injections that you just *can't* have the C compiler generate.

## Calling C from ASM

The solution is pretty simple really, just write some ASM, and somewhere in it you `bl` or `bl` to `bx` to the C function, as if its name was a simple label in your ASM:

```
.thumb

some_asm:
	push {r0-r3}
	
	@ let's say we are setting up arguments for our function
	mov r0, r2
	mov r1, r3
	
	ldr r3, =some_c_function
	bl BXR3
	
	pop {r0-r3}
	
	@ let's assume this is the hooked-into routine's old code that we replaced
	nop
	nop
	nop
	
	ldr r3, =#0x800DEAD @ return location
BXR3:
	bx r3
```

*Then*, instead of throwing that into "Assemble ARM.bat", just `make` an object file, and then we get it through `lyn`. We get this:

```
SHORT $B40F $1C10 $1C19 $4B04 $F000 $F805 $BC0F $46C0 $46C0 $46C0 $4B01 $4718
POIN some_c_function
BYTE $AD $DE $00 $08
```

Hey, `some_c_function` got referenced in EA! This works, we can now get our C function through `lyn` too and we have something like this:

```
PUSH
ORG (CURRENTOFFSET+$1); some_c_function:
POP
SHORT $Whatever $46C0
```

If we put those together we get something that assembles correctly and everything is nice yay.

## Calling ASM from C

So in this part, we are going back to messing with ASM a bit more. I think you get the picture: the C compiler already generates pretty "open" (as in: easily interfacable) object files. Most of this document is about integrating C in hacking, and not really the opposite... Whatever it is.

For C or, to be more specific, the linker to know how to call your asm, you need to *expose* the symbol pointing to the part of your asm you want to call (and also it needs the symbol to be of "function" type, so that it knows you're not accidentally calling data as a routine)

So here's the two *assembler directives* we are going to use:

```
.global <name>
.type   <name>, %function
```

If you paid attention earlier (when I told you about making object files containing information about the game), you'll notice that those are the same directives I used then.

`.global <name>` *exposes* the symbol to the outside (in other words, external object files can "see" it).

`.type <name>, %function` marks the symbol as being of "function" type, so that the outside knows that this symbol can be the target of a function call.

Here's some example ASM:

```
.thumb

.global get_magic_number
.type   get_magic_number, %function

get_magic_number:
	mov r0, #42
	bx  lr
```

Now, our C file:

```
#include "gbafe.h"

void some_asmc() {
	eventSlot[0xC] = get_magic_number();
}
```

And I don't know about you but I get this:

```
<file>.c: In function 'some_asmc':
<file>.c:4:19: warning: implicit declaration of function 'get_magic_number' [-Wimplicit-function-declaration]
  eventSlot[0xC] = get_magic_number();
                   ^~~~~~~~~~~~~~~~
```

oops, I forgot to include the *declaration* of our asm function in the C file. Happens.

```
#include "gbafe.h"

int get_magic_number();

void some_asmc() {
	eventSlot[0xC] = get_magic_number();
}
```

Better.

## Calling conventions

So I wrote another big document on this subject, so I'll just go over the important details here.

C function signatures hold the information neccessary for the C compiler to know how to handle the called function's arguments & return value. Simple arguments & return values are pretty simple to understand: each argument a register (up to `r3`), and the return value in `r0` after the function call.

There are some ambiguous cases tho, and we can tell they're ambiguous since beginner ASM hackers have different ways of tackling them.

The first (obvious) one is the case where you have more than 4 arguments. Basic logic would dictate you continue onto `r4`, `r5` and so on... But then what happens when you reach `r11`? You can't use `r12` since it can be used to redirect the call (see the aforementionned doc for details), and after that its the stack pointer...

The stack! Yes that's exactly where extra arguments are going to be. In fact, convention doesn't wait until `r11` for that, after `r3` (fourth argument), the arguments are stored at `[sp+00]`, `[sp+04]`, etc.

So a function with the following signature

```
void some_function(int a, int b, int c, int x, int y);
```

Will have the following argument map:

- `r0` = `int a`
- `r1` = `int b`
- `r2` = `int c`
- `r3` = `int x`
- `[sp+00]` = `int y`

Second case: we have an argument that can't fit in a register (or any word in general). That one is kinda simple: we split the argument in mutiple parts, and each part is its own argument. It is the called function's responsability to interpret the different parts correctly.

For example:

```
struct xyz { short x, y, z; }
void some_function(struct xyz positionInThreeDee, int b);
```

Will have the following argument map:

- `r0` = `positionInThreeDee` part 1 (`xyz.x` & `xyz.y`)
- `r1` = `positionInThreeDee` part 2 (`xyz.z` & padding)
- `r2` = `int b`

Third case: we have a return value that can't fit in a register *and isn't either a `long long`, a `double`, a `long double`, or a complex* (those cases, or any other case of "primary type that's larger than a word" that I may have forgotten, return arguments in `r0` *and* `r1`).

In this case, an extra argument is prepended (added before all the others) to the list: it's a pointer to where the return value will get written to.

For example:

```
struct BigStruct some_function(int a);
```

Will have the following argument map:

- `r0` = `struct BigStruct*` (somewhere to write the return value)
- `r1` = `int a`

There's probably other corner case scenarios I forgot to mention here. If you have any doubt: I recommend you write a test function, compile it to asm and see the result for yourself.
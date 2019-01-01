# Advanced "linking"

In the previous (first) example, I taught you how to make the game call your C (by exposing C functions through EA and then doing the same thing as you'd do with asm). But how do we do the opposite? How do we call the already existing parts of the game with C?

The game was almost definitely written in C (crazy, I know). This doesn't really mean too much to us; but it does mean that each function follow ARM C calling conventions. In other words, we don't need to do anything crazy to interface our code with the game's functions (we just need to let the compiler and/or `lyn`/EA know where those functions are).

In this chapter, I'll use the simple example of the "`GetGameTime`" function (This is just the name I gave it, there's no "official" name to it), located in FE8U at `0x08000D28`, that returns the game time (in frames) and takes no arguments. Its signature is the following:

```c
int GetGameTime(void);
```

_**Note**: when calling game functions from C, unlike from ASM, you want to declare their signature. The compiler needs this information to behave properly._

## Declaring pointers in the source

If you did some ASM Hacking before (you probably did), you may have done the following: you defined the address of a game routine you wanted to call, loaded that and "`bl` to `bx`"ed to it (or "`.short 0xF800`"ed to it). And you totally can do a similar thing in C too! I even kinda did that in the example when writing to event slots. Those were simple int pointers, but you can do the same thing with function pointers, look:

```c
static const int(*GetGameTime)() = (int(*)()) (0x08000D29); // note the thumb bit here.

static int* const sEventSlot = (int* const) (0x030004B8);

/*!
 * Gets game time (in frames) and stores it to event slot C.
 */
void asmc_get_time(void) {
	sEventSlot[0xC] = GetGameTime();
}
```

I want to show you that this indeed works. Let's look at the asm (The comments are my addition, so that things were a bit more clear):

```arm
asmc_get_time:
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

_**Note**: As it was noted in replies below, you can also achieve this by using raw expressions or `#define`s instead of static constants, but the general concept is the same._

Ok so that works, we're done now. Right? Well sure you can go ahead and do it that way if you want I, won't judge (Ok maybe I will just a teeny tiny bit).

I'll ask you this: What if @7743 wants to port your hack to FE8J (or FE8E lol). Since you basically "hardcoded" the game's addresses in your source you need to edit all of that to support FE8J. This means you end up with two different code bases that you have to update, which is kind of eh (imagine doing this for hack with 5-6 files of a couple hundred lines each).

Of course this can be mitigated by using a header for all the declaration of the game functions there, and using ifdef guards to allow to support for mutiple games, which you can also totally do and I won't judge you (or, again, maybe I will). In my opinion this starts to get messy and I think we can do something more elegant.

## Creating a "library" for interfacing with the game

_**Note**: for the sake of this guide, I will demonstrate making a new library and reference from scratch. For "real" hacking I use and provide [a fairly big existing library and reference](https://github.com/StanHash/FE-CLib) that I recommend you use too after you understand how it works._

So here's the deal: we are going to decouple the *declaration* of what the game provides us (including the *signature* of functions), and the *definition* of where it is.

The *declaration* part, you probably guessed it, we are going to put that in a good old C *header* file. Let's call it, `gbafe.h`. It would contain function declarations, of course, but also maybe eventually structure definitions for data from the game (like say, the [unit struct](https://github.com/StanHash/FE-CLib/blob/master/include/gbafe/unit.h)) and object declarations (such as the active unit pointer). From that all we need to do in our source file is to `#include` it and use it.

Here's the header file containing "`GetGameTime`" and "`gEventSlot`" declarations:

```c
#ifndef GBAFE_H
#define GBAFE_H

extern int gEventSlot[];

int GetGameTime(void);

#endif // GBAFE_H
```

_**Note** about why I went from `sEventSlot` to `gEventSlot`: `s` stands for static and `g` stands for global. It's a relatively common naming convention in the world of C programming (I think, at least the decomp uses it)._

Ok so I guess now I need to explain a bit more about symbols and how C names translate to them. See the `gEventSlot` declaration? It will generate a (undefined) `gEventSlot` symbol. The value of that symbol is expected to be the *address of the object it represents*.

This is why I decided to declare `gEventSlot` as an array and *not* a pointer, because if I declared a pointer, It would expect as value the address of a pointer, but the address I want to give it is the address of the event slot value array (`0x030004B8`), and the data there isn't a pointer, but the value of slot 0 (which so happens to be 0 most of the time, not really a useful pointer).

Here's the C file we'll use:

```c
#include "gbafe.h"

/*!
 * Gets game time (in frames) and stores it to event slot C.
 */
void asmc_get_time(void) {
    gEventSlot[0xC] = GetGameTime();
}
```

Generated ASM:

```arm
asmc_get_time:
	push  {r4, lr}
	bl    GetGameTime
	ldr   r3, .L2
	str   r0, [r3, #48]
	pop   {r4}
	pop   {r0}
	bx    r0
.L2:
	.word gEventSlot
```

Notice that the generated code only uses a standard `bl`, which may cause problems (mainly because the main game code isn't usually within "`bl`-range" of our inserted hacks), so how do we make it a safer `bl` to `bx`?

Note: if you are using `lyn`, it is even more important to transform `bl`s into `bl` to `bx`es, since `lyn` can't *relocate* (that's the term for when a reference in an object file (aka a *relocation*) is being resolved properly) *relative* references (such as a `bl`) to external symbols. This comes from the simple fact the `lyn` doesn't know where the object it links will be (since that's for EA to decide).

So, there's two ways we can do that: either during linking, or during compilation.

#### long calls during linking

`lyn` comes with the `-longcalls` option, This tells `lyn` that when it finds itself in a situation where it can't properly relocate a symbol because the relocation isn't absolute (for example: when relocating a `bl`), it is allowed to add extra code (a "veneer") to "make" it absolute. Example:

- Without `-longcalls`:

```
PUSH
ORG (CURRENTOFFSET+$1); asmc_get_time:
POP
SHORT $B510
SHORT ((((GetGameTime-4-CURRENTOFFSET)>>12)&$7FF)|$F000) ((((GetGameTime-4-CURRENTOFFSET)>>1)&$7FF)|$F800)
SHORT $4B02 $6318 $BC10 $BC01 $4700
POIN gEventSlot
```

- With `-longcalls`:

```
PUSH
ORG (CURRENTOFFSET+$1); asmc_get_time:
POP
{
PUSH
ORG (CURRENTOFFSET+$15); _LP_GetGameTime:
POP
SHORT $B510
SHORT ((((_LP_GetGameTime-4-CURRENTOFFSET)>>12)&$7FF)|$F000) ((((_LP_GetGameTime-4-CURRENTOFFSET)>>1)&$7FF)|$F800)
SHORT $4B02 $6318 $BC10 $BC01 $4700
POIN gEventSlot
SHORT $4778 $46C0
WORD $E59FC000 $E12FFF1C
POIN GetGameTime
}
```

Whoah that's a lot of new stuff. In realtity that's only 16 extra bytes (2 SHORTS, 2 WORDS, 4 BYTES at the very end of the thing). But there's also a new symbol, `_LP_GetGameTime` ~~that probably shouldn't be here because it should know how to optimize it away so that's a bug for me to fix but in this particular case it's useful for getting my point accross~~, that replaces the regular `GetGameTime`, and this time it is properly defined and it even doesn't pollute the global EA namespace since it's enclosed in curly brackets.

The extra 16 bytes at the end are a piece of asm that "transforms" the `bl` into a `bl` to `bx`. It's different to a regular `bl` to `bx` because the setup (loading of the target address) here is done *after* the `bl`.

Anyway, since the call is transformed, `lyn` could relocate the `GetGameTime` symbol (if it knew where it was, but we'll get to that). Even better: we aren't limited by the potential limitation of the range of the `bl` instruction (+-4MB). Mission accomplished... But I think we can be better.

#### long calls during compilation

There's multiple ways to go on this:

- We could use the compiler and target-specific function attributes in our header to specifiy we want to long call:
  
  ```c
  int GetGameTime(void) __attribute__ ((long_call));
  ```
  
  That's honestly only really okay for quick testing: if we start adding other signatures it can get tedious really fast (not to mention pretty ugly).

- We could use the compiler and target-specific `#pragma long_calls`:
  
  ```c
  #pragma long_calls
  
  int GetGameTime();
  
  // as many other function declaration as you want
  
  #pragma long_calls_off
  ```
  
  This `long_calls` pragma applies the `long_call` attribute automatically to all function declarations encountered until the next `long_calls_off` pragma. This is fine and I've been using this method for the last year now, but I feel like the next and last one may be the better way.

- We could use the compiler and target-specific program option `-mlong-calls`, which makes *all* references to outside code a "long call". This may be a bit unnecessary for function calls accross our own files (that would probably be inserted close together aka within `bl`-range), but this allows us to move the details related to the limitations of our setup *outside* of the source itself which I feel may be preferable.
  
  We can just add `-mlong-calls` to the definition of the `CFLAGS` variable in our makefile.

In all three cases we get this ASM:

```arm
asmc_get_time:
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
	.word gEventSlot

.L4:
	bx    r3
```

A good old `bl` to `bx`. Wonderful. And it does look better than what `lyn` did, which makes sense since we tackled the problem at an earlier point in the compilation process.

Ok so now comes the *definition* part. I'll show you *two* ways to handling that: through a "reference object" (my recommendation), and through EA (for the lazy ones).

### Definition through a "reference object"

In this method, we *define* the symbols we need in an external object file: the "reference object". This file and *only* this file (in theory) is game-specific, since this is the only file where we will have actuall addresses in it.

This source file will *not* be a C file, but a good old ASM file. We won't be putting any actual ASM in it though, we will rather be abusing assembler directives to *generate an object file containing the symbol definitions we need*.

Here's mine:

```arm
.macro SET_FUNC name, value
	.global \name
	.type   \name, %function
	.set    \name, \value
.endm

.macro SET_DATA name, value
	.global \name
	.type   \name, %object
	.set    \name, \value
.endm

SET_DATA gEventSlot,  (0x030004B8)

SET_FUNC GetGameTime, (0x08000D28+1)
```

Note that I'm defining through helper macros I also defined. For now it seems kinda redundant but later when we start to add dozens of extra functions and/or references to data, you'll thank me.

Anyway, I called it `fe8u.s` (I'm willingly choosing a different extension to the one for generated asm from C files, as it allows me to differentiate between generated asm and hand-written asm (gets useful when writing `clean` rules in the makefile later)).

Hey! We don't even have a rule for making object files from asm in our makefile (this probably means that I'm doing a good job), so let's remedy this. Add this to your makefile:

```makefile
# ASM to OBJ
%.o: %.s
	$(AS) $(ARCH) $< -o $@
```

Now we can `make fe8u.o` (we can also `make fe8u.lyn.event`, but this will just generate a blank file, as there isn't any data nor local symbols defined in it, and `lyn` doesn't expose absolute symbols).

Ok so now what? We have a nice object file with our symbols defined in it, and a nice header with our symbols declared... but how do we use all that?

The awnser is: we need to link the object file generated from that C file with `fe8u.o`. When we do that, the symbols referenced by the C object will be sustitued by their definition from the `fe8u.o` object. To do that, we simply pass them both to `lyn`:

```sh
$ ./lyn <myfile>.o fe8u.o
```

It gives me this:

```
PUSH
ORG (CURRENTOFFSET+$1); asmc_get_time:
POP
SHORT $B510 $4B04 $F000 $F80A $4B03 $6318 $BC10 $BC01 $4700 $46C0
BYTE $29 $0D $00 $08 $B8 $04 $00 $03
SHORT $4718 $46C0
```

Sweet. We linked our objects together.

#### (Makefile) Automatically making & linking the reference object

I'm going to assume we need that reference object for *all* of our `lyn` links. That way we can take the rule for making `.lyn.event` files and modify it accordingly:

```makefile
# OBJ to EVENT rule
%.lyn.event: %.o fe8u.o
	$(LYN) $< fe8u.o > $@
```

If you aren't familiar with makefiles: I added a second *dependency* to the pattern rule for generating `.lyn.event` from `.o` files. This means that each time you require a `.lyn.event`, it will first make sure that both the corresponing `.o` file and the `fe8u.o` file are *up to date* (aka younger than their own dependencies).

This story about makefiles & up-to-dateness will come again later when we will learn how to generate dependency definitions for our C files (that are including other files, on which the source *depends* on).

Anyway, this simple change makes sure that the reference is built before building the `.lyn.event` file.

Also the `lyn` call was changed to include the reference too.

You could also define a Make variable that holds the reference object to link against. For example:

```makefile
# reference object
LYNREF := fe8u.o
```

And the rule then becomes

```makefile
# OBJ to EVENT rule
%.lyn.event: %.o $(LYNREF)
	$(LYN) $< $(LYNREF) > $@
```

### Definition through EA

When `lyn` can't relocated something, it doesn't fail. Instead it just writes the name of the targetted symbol in place, letting EA handle it and probably fail in its place.

But we can also take this to our advantage. If we get our object and `lyn` it, we get this:

```
PUSH
ORG (CURRENTOFFSET+$1); asmc_get_time:
POP
SHORT $B510 $4B04 $F000 $F80A $4B03 $6318 $BC10 $BC01 $4700 $46C0
POIN GetGameTime gEventSlot
SHORT $4718 $46C0
```

Direct reference to the missing symbols can be seen. So what do we do? Well, we `#define` them!

```
#define GetGameTime "(0x08000D28+1)"
#define gEventSlot  "(0x030004B8)"
```

ez. Know that since EA 11.1 (the version in which I did stuff shh that's a secret) (Note: this is *not* yet part of ColorzCore), A feature exists that allows us to do the following:

```
GetGameTime = 0x08000D28+1
gEventSlot  = 0x030004B8
```

Anyway, done. Put that anywhere (if you used `#define`, it needs to be brefore the `lyn` output), and the `lyn` output *will* assemble and link correctly. Hurray!

This is obviously easier than to go through all the hassle of making another object file and linking it via a `lyn` call and all, and also way more clean that the brute way of defining const function pointers. I'm guessing most people reading this ~~(that's probably not a lot of people)~~ will choose to use this method over the other two.

The issue I find with this method is in the hack distribution side of things. I think making the smallest (in event file size/EA computation needs), easiest to install (`#include` and be done), and less polluting (as in: polluting the EA global namespace with useless junk) hacks is a priority (coming from me and my MSG Helpers & Ultra-Flexible Heroes Movement Hacks, this would probably sound somewhat inconsistent to some people).

~~It also would suck if one day you decide to not use EA anymore~~.

But still, I think the less EA does, and the more processing you can have done before the "EA" phase, the better it is (EA does already enough as is).

# Integrating ASM & C

Ok, so you already know how to call C from Events (`ASMC`, see our first example) and probably have an idea of how to call C with EA `Extensions/Hack Installation.txt` Macros (`jumpToHack`, `callHack_rx`, ...), since it's basically the same in a different context.

Here we are going to see how to integrate your C code & regular "raw" ASM. This will be probably most useful when setting up more elaborate hooks and you need to setup some very precise ASM injections that you just *can't* have the C compiler generate elegantly.

## Calling C from ASM

The solution is pretty simple really, just write some ASM, and somewhere in it you `bl` or `bl` to `bx` to the C function, as if its name was a simple label in your ASM:

```arm
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

So in this part, we are going back to messing with ASM a bit more. The C compiler already generates pretty "open" (as in: easily interfacable) object files, but this isn't necessarily the case for ASM.

For C or, to be more specific, the linker to know how to call your asm, you need to *expose* the symbol pointing to the part of your asm you want to call (and also it needs the symbol to be of "function" type, so that it knows you're not accidentally calling data as a routine)

So here's the two *assembler directives* we are going to use:

```arm
.global <name>
.type   <name>, %function
```

If you paid attention earlier (when I told you about making object files containing information about the game), you'll notice that those are the same directives I used then.

`.global <name>` *exposes* the symbol to the outside (in other words, external object files can "see" it).

`.type <name>, %function` marks the symbol as being of "function" type, so that the outside knows that this symbol can be the target of a function call.

Here's some example ASM:

```arm
.thumb

.global get_magic_number
.type   get_magic_number, %function

get_magic_number:
	mov r0, #42
	bx  lr
```

Now, our C file:

```c
#include "gbafe.h"

int get_magic_number(void);

void asmc_get_magic_number(void) {
	gEventSlot[0xC] = get_magic_number();
}
```

Assemble/compile and lyn both, `#include` them and it should work!

## Calling conventions

[I wrote another fairly big document on this subject](https://feuniverse.us/t/doc-asm-conventions/3350?u=stanh), so I'll just go over the important details here.

C function signatures hold the information neccessary for the C compiler to know how to handle the called function's parameters & return value. Simple parameters & return values are pretty simple to understand: each parameter corresponds to a register (up to `r3`), and the return value to `r0` after the function call.

There are some ambiguous cases though, and we can tell they're ambiguous since beginner ASM hackers have different ways of tackling them.

The first (obvious) one is the case where you have more than 4 parameters. Basic logic would dictate you continue onto `r4`, `r5` and so on... But then what happens when you reach `r11`? You can't use `r12` since it can be used to redirect the call (see the aforementionned doc for details), and after that its the stack pointer...

The stack! Yes that's exactly where extra arguments are going to be. In fact, convention doesn't wait until `r11` for that, after `r3` (fourth parameter), the arguments are stored at `[sp+00]`, `[sp+04]`, etc.

So a function with the following signature

```c
void some_function(int a, int b, int c, int x, int y);
```

Will have the following parameter map:

- `r0` = `int a`
- `r1` = `int b`
- `r2` = `int c`
- `r3` = `int x`
- `[sp+00]` = `int y`

Second case: we have a parameter that can't fit in a register (or any word in general). That one is kinda simple: we split the parameter in mutiple parts, and each part is its own parameter. It is the called function's responsability to interpret the different parts correctly.

For example:

```c
struct xyz { short x, y, z; }
void some_function(struct xyz positionInThreeDee, int b);
```

Will have the following parameter map:

- `r0` = `positionInThreeDee` part 1 (`xyz.x` & `xyz.y`)
- `r1` = `positionInThreeDee` part 2 (`xyz.z` & padding)
- `r2` = `int b`

Third case: we have a return value that can't fit in a register *and isn't either a `long long`, a `double`, a `long double`, or a complex* (in those cases, the return value is split using the same rules as parameters, and can use registers `r0` through `r3`).

In this case, an extra parameter is prepended (added before all the others) to the list: it's a pointer holding the address of where to write the return value. The function also still returns that address.

For example:

```c
struct BigStruct some_function(int a);
```

Will have the following parameter map:

- `r0` = `struct BigStruct*` (somewhere to write the return value)
- `r1` = `int a`

There's probably other corner case scenarios I forgot to mention here. If you have any doubt: I recommend you write a test function, compile it to asm and analyse the result for yourself. ~~Or read the doc~~.

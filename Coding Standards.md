# C++ Coding Standards

Revision 1.0\
Created on June 26^th^, 2000\
Last Revised on March 31^st^, 2020\
Adapted from "C++ Coding Standards" The Corelinux Consortium

[1. Scope](#scope)\
[  1.1 Document Overview](#document-overview)\
[2. General Principles](#general-principles)\
[3. Comments](#comments)\
[4. Code Layout](#code-layout)\
[  4.1 Braces and Parenthesis](#braces-and-parenthesis)\
[  4.2 Declarations](#declarations)\
[  4.3 Keyword Constructs](#keyword-constructs)\
[  4.4 Preprocessor](#preprocessor)\
[  4.5 Spaces](#spaces)\
[  4.6 Wrapping](#wrapping)\
[5 Naming Conventions](#naming-conventions)\
[  5.1 Files and Directories](#files-and-directories)\
[6. Usage](#usage)\
[  6.1 Conditionals](#conditionals)\
[  6.2 Loop Constructs](#loop-constructs)\
[  6.3 Data](#data)\
[  6.4 Constructors and Destructor](#constructors-and-destructor)\
[  6.5 Initialization](#initialization)\
[  6.6 Declaration](#declaration)\
[  6.7 Programming](#programming)\
[  6.8 Class and Functions](#class-and-functions)\
[  6.9 Templates and Template Functions](#templates-and-template-functions)\
[  6.10 Inheritance](#inheritance)\
[  6.11 Object-Oriented Considerations](#object-oriented-considerations)\
[  6.12 Error Handling](#error-handling)\
[  6.13 Exception Specification](#exception-specification)\
[7. File Layout](#file-layout)\
[8. Header File Layout](#header-file-layout)\
[9. Special Care and Handling](#special-care-and-handling)\
[10. References](#references)

# 1. Scope

The principle function of this document is to establish a consistent
standard, which will provide for easier maintenance of code. This will
benefit the team and the project in that those who are new to the code
can quickly orient themselves, and thereby sooner become productive
members of the team. It is intended to be a dynamic document and can be
reviewed as needed. It is recommended that each programmer keep a copy
on hand also.

## 1.1. Document Overview

The following document sections contain standards, guidelines, and
rationales. Guidelines must be adhered to unless there is compelling
reason to deviate. Deviation from a guideline must be discussed and
approved during the code walk-through. A standard is an item to which
compliance is mandatory. Deviation from a standard must be discussed,
approved, and signed-off on by the team lead during the code
walk-through. Rationales have been used where necessary to explain the
meaning of an item, or why it was chosen.

**General Principles -** This section contains the basic philosophy a
developer should keep in mind while coding.

**Comments -** This section deals with the placement and contents of
comments in the code.

**Code Layout** - This section has to do with the alignment of the code,
white space, declarations and keywords, and where they should all be
located.

**Naming Conventions** - This section contains the structure for naming
classes, functions, files, and directories.

**Usage** - This section concerns the \'how\' and \'when\' certain
constructs should be used (for example, loops, inheritance, error
handling, etc.)

**File Layout** - This section applies to where things should be located
in header files and modules.

**Coding Examples** - This section contains an example of a header file
and module which conform to the C++ Coding Standard.

# 2. General Principles

The primary goal of the coding standard is maintainability. Other
important considerations that relate to the spirit of the standard
include correctness, readability, consistency, extensibility,
portability, clarity, and simplicity. When in doubt, the programmer
should strive for clarity first, then efficiency.

Think of the reader. Do not just write for yourself. Keep it simple.
Break down complexity into simpler chunks. Clearly comment necessary
complexity. Be explicit. Avoid implicit or obscure language features. Be
consistent. Minimize scope, both logical and visual.

# 3. Comments

**Guideline 1** - Be clear and concise. Say what is happening and why.
Do not restate code.

**Guideline 2** - Keep code and comments visually separate.

**Standard 1** - Use top of file comments for all files. The comments
should be DOXYGEN compatible

Here is an example of a good header for a file:
```
///=====================================================================
/// \\file IRenderContext.h
/// \\brief Header file for the Rendering contexts
/// i.e. rendering surface inside windows
/// \\date 09/29/2002
/// \\author Kenneth Hurley
///=====================================================================
```
**Standard 2** - Use header comments for all functions. The size of the
comment should mirror the size and complexity of the code. Class
interface functions and procedures should be commented in the header.

**Standard 3 --** Include comment headers for interfaces inside the .h
file. A well-formed .h file should look like the following:
```
    ///=====================================================================
    /// \file	IRenderContext.h
    /// \brief	Header file for the Rendering contexts
    ///				  i.e. rendering surface inside windows
    /// \date	09/29/2002
    /// \author	Kenneth Hurley
    ///=====================================================================

    #ifndef IRENDERCONTEXT_H
    #define IRENDERCONTEXT_H

    class IConfig;
    class IRenderView;
    class IRenderWindow;

    /// \class IRenderContext
    /// \brief Context for Rendering objects into.  
    ///
    ///	Render contexts have rendering windows
    /// attached to them before they can be used.
    class IRenderContext
    {
    public:
    	/// Attach a Rendering windows to a rendering context.
    	/// \param rendWin - The window to attach to the context
    	/// \return false on failure
    	virtual BOOL AttachRenderWindow(IRenderWindow *rendWin) = 0;
    	/// Get the number of rendering views inside the context
    	/// \return the count of current rendering views
    	virtual DWORD GetRenderViewCount() = 0;
    	/// Get one of the views associated with the context
    	/// \param index - index # of the internal rendering view
    	/// \param pRV - pointer to receive the IRenderView interface pointer
    	/// \return false on failure
    	virtual BOOL GetRenderView(DWORD index, IRenderView **pRV) = 0;
    	/// Add a rendering view to the rendering context
    	/// \param pRV - the renderview to add to the context
    	/// \return false on failure
    	virtual BOOL AddRenderView(IRenderView *pRV) = 0;
    	/// Delete one of the rendering views in the context
    	/// \param index = index # of the internal rendering view
    	/// \return false on failure
    	virtual BOOL DeleteRenderView(DWORD index) = 0;
    	/// Get the configuration meta-data for the rendering context
    	/// \return interface to configuration meta data
    	virtual IMeta *GetConfig() = 0;
    	/// Get the parent rendering window for this context
    	/// \return interface to the parent rendering window
    	virtual IRenderWindow *GetParentWnd() = 0;
    };

    #endif	  // #ifndef IRENDERCONTEXT_H
```
**Standard (.cpp) 1** - Use only the C++ comment style (double slashes)
for single line comments.

**Guideline 3** - For block comment styles either C++ (double slashes)
or C style (/\* \... \*/) can be used.

```
// \...
```
\- OR -

```
// \... //
```

\- OR -

```
/\* \... \*/
````

**Guideline 4** - Prefer block comments to trailing comments. Use block
comments regularly. Only use trailing comments for special items.

**Standard 4** - Trailing comments must all start in the same column in
the function.

**Standard 5** - Trailing comments at a closing brace are indented one
level from brace.

**Standard 6** - Block comments are at the same indentation level as the
block they describe.

**Standard 7** - Ensure comments are correct (and stay correct).

# 4. Code Layout

**Guideline 5** - Write code in a series of chunks.

**Guideline 6** - Use block comments to separate the chunks.

**Standard 8** - Put one statement per line, except with in-line code in
a header file.

**Guideline 7** - Functions shall have a single exit point.

> Rationale: Multiple exit points usually add to the complexity of a
> function. Post conditions and invariant checks must also be performed
> prior to each return.

**Standard 9** - Indentation level is (1) one tab or (4) four spaces.

## 4.1. Braces and Parenthesis

Standard 10 Braces shall be aligned using Ulman style where the braces
are at the same scope as the statement that proceeds them and the code
within the braces is indented one level. Braces are always on a line by
themselves.
```
    void doSomething( void )
    {
    	if( x != y )
    	{
    	    y = x;
    	}
    	else
    	{
    	    ...
    	}
    }
```
\- NOT -
```
    void doSomething( void )
    {
    	if( x != y )
    	{
    	y = x; // should be indented
    	}
    	else
    	{
    	...
    	}
    }
```
\- OR -
```
    void doSomething( void )
    {
    	if( x != y )
    	    { // brace is not the same scope
    	        y = x;
    	    }
    	else
    	    {
    	        ...
            }
    }
```
\- OR -
```
    void doSomething( void )
    {
    	if( x != y ){ // brace is not on a line by itself
    	    y = x;
    	}
    	else {
    	    ...
    	}
    }
```
**Standard 11** - While, for and if statements shall always use braces,
even if they are not syntactically required.

**Guideline 8** - Use parenthesis to group within a statement and to
emphasize evaluation order.

**Guideline 9** - Avoid unnecessary parentheses.

**Guideline 10** - Avoid deep (more than three) levels of parenthesis
nesting.

## 4.2. Declarations

**Standard 12** - Order declarations as storage class specifier, type
specifier as described in ISO/IEC 14882 C++ standard, section 7.1.

**Standard 13** - Start each declaration on a new line.

**Standard 14** - Enumeration declarations will be declared with named
constants in upper case and the identifier specified as described in
Naming conventions.
```
    enum Identifier
    {
    	ONE,
    	TWO,
    	THREE
    };
```
\- OR -
```
    enum Identifier
    {
    	ONE = 1,
    	TWO,
    	THREE
    };
```
**Standard 15** - All variables must be initialized.

**Guideline 11** - Use vertical alignment to ease scanning of
declarations.
```
    String 	aStringToUse;
    Int 	anInt;
    Real 	aRealNumberToUse;
```
\- instead of -
```
    String aStringToUse;
    Int anInt;
    Real aRealNumberToUse;
```
**Standard 16** - Do not create anonymous types (structs), except in a
class declaration where a private structure is declared.

## 4.3. Keyword Constructs

**Guideline 12** - Most if statements should be followed by an else
statement.

**Standard 17** - Nested else if statements shall be indented as normal
statements, the if shall appear on the same line as the else.

**Standard 18** - Indent cases one level from the switch and indent the
code one level beyond the case. The break statement is at the same
indentation level as the code.

**Standard 19** - All switch statements shall have a default case.
```
    switch( variable )
    {
    	// ...
    	case 1:
    	    break;
    	// ...
    	case 2:
    	    break;
    	// ...
    	default:
    	    break;
```
## 4.4. Preprocessor

**Standard 20** - Put the while in a do while statement on the same line
as the closing brace.
```
    do
    {
        ++x;
    } while(x < y);
```
**Guideline 13** - Preprocessor directives should be avoided whenever
possible.

**Standard 21** -- For header files use the standard \#include method:
```
    #include <Common.hpp>
```
**Standard 22** - Multi-statement macros shall have one statement per
line.
```
    #define MULTIPLE_LINE_MACRO( s ) \
    ++(s); \
    (s) = ((s) % 3 ? ++(s) : (s) )
```
## 4.5. Spaces

**[NOTE:]{.underline}** Adhere to the indentation standard.

**Standard 23** - Do not use spaces in object de-references.
```
    val = *pFoo; // ok
    val = * pFoo; // wrong
```
**Standard 24** - Do not space between an unary operator and its
operand, but do space the other side.

**Standard 25** - Balance spacing on either side of binary operators.

**Standard 26** - Do not space before separators ( semicolon, argument
comma separator ) but do space the other side.

**Guideline 14** - It is acceptable to put a space before the semicolon
that terminates a statement, as long as it is consistent throughout the
function.

**Standard 27** - Balance spacing inside parenthesis.

**Standard 28** - Do not space between function name and parenthesis,
but space after open parenthesis and before close parenthesis with the
exception of no arguments. e.g.
```
    void doFunction( void ) // ok
    void doFunction( ObjectRef aRef ) // ok
    void doFunction(ObjectRef aRef) // wrong
    void doFunction( ObjectRef aRef) // wrong
    void doFunction() // ok
```
**Standard 29** - Use blank lines before and after block comments.

**Standard 30** - Use vertical alignment to indicate association.

## 4.6. Wrapping

**Guideline 15** - No line of code should extend beyond column 78.

Rationale: When the audience for the source and headers of a project may
reach thousands, if not more, readability and continuity become prime
factors for comprehension. Additionally, in a multideveloper
environment, the potential for disjoint style is personified with no
restrictions on column length.

**Standard 31** - When wrapping lines, indent the continuation line past
the current indent column.
```
    Int val(2);
    cout << "This is an example where I wrap "
    	<< val
    	<< " lines of code" << endl;
```
**Standard 32** - Wrap assignments past the equal sign.
```
    ObjectMapConstIterator aItr;

    aItr = theMapOfObjects.begin();
```
**Standard 33 -** Wrap conditional expressions after the operators.
```
    if( theNameOfTheGame == aGameName &&
    	theTimeBeingPlayed > aLimit )
    {
    	// ...
    }
```
**Standard 34** - Wrap for statements after the semi-colons.
```
    for (itMass = mass.begin(); itMass != mass.end(); 
    	itMass++)
```
**Standard 35** - Wrap long function signatures after a parameter comma
with indentation.
```
    void ClassMethod::setValues(ObjectCref a1, ObjectCref a2, StringCref aName,
    	IntCref aValue, ...)
    {
    	...
    }
```
# 5. Naming Conventions

**Standard 36** - Spell words using correct English spelling. For the
most part, avoid abbreviations.

Rationale: The reader much better understands the semantics of a type
when they have names like \"SpeakerCabinet\" instead of \"spkcb\".

**Guideline 16** - Make names clearly unique. Avoid similar-sounding
names and similarly-spelled names.
```
    Int 	aCount;
    String 	aName;
    Object 	aPerson;
```
\- INSTEAD OF -
```
    Int x1;
    String x2;
    Object x3;
```
**Standard 37 -** Make all identifiers unique within a function.

**Standard 38** - Use mixed case to distinguish name segments instead of
underscores.
```
    WellFormedObject 	aObject; // ok
    non_standard_form aObject; // wrong
```
**Standard 39 -** Types start with an upper case letter and use mixed
case to separate name segments. (i.e. String, BigCar).

**Standard 40** - Variables and objects names that are data members of a
class start with a \`m\_\' and use mixed case thereafter:
```
    class Foo
    {
    public:
    	//
    protected:
    	String m_Name;
    };
```
**Standard 41** - Variables and objects names that are arguments or
locals start with lower case \`a\'. (i.e. String aName; ).

**Guideline 17 -** Only use short variable names when they have limited
scope and obvious meaning. Beware of them causing confusion.

**Standard 42** Use capital letters to begin new name segments within
the name.

**Guideline 18** - Name functions with verb-noun (verb object)
combinations.

**Guideline 19** - Name variables and structures with noun, adjective
noun combinations.

**Standard 43** - Accessor methods start with the word \'Get\' and
should be const.

**Standard 44** - Boolean accessor functions start with \'Is\' and
return bool.

**Standard 45** - Mutator procedures start with the word \'Set\' and
don\'t return values.
```
    class Foo
    {
    public:
    	//
    	// Accessor
    	//
    	String GetName( void ) const;

    	bool IsNameEmpty( void ) const;
    	//
    	// Mutator
    	//
    	void SetName( String aName );

    protected:
    	String m_Name;
    };
```
**Standard 46 -** Factory instantiation functions start with the word
\'Create\'.
```
    ThreadPtr CreateThread( void );
```
**Standard 47** - Factory destruction functions start with the word
\'Destroy\'.
```
    void DestroyThread( ThreadPtr );
```
## 5.1. Files and Directories

**Standard 48** - Use project names in source include statements:
```
    #if !defined(__SOMETHING_HPP)
    #define (__SOMETHING_HPP)
    #if !defined(__COMMON_HPP)
    #include <corelinux/Common.hpp> // Correct
    #include <Common.hpp> // While also correct,
    	// there is too much assumption on environment
    #endif
    ...
    #endif
```
**Guideline 20** - Name files like variables, describing the functions
they contain. Long file names are encouraged.

**Standard 49** - Use .cpp and .hpp for class definition source and
header file suffixes.

**Guideline 21** - Use .c and .h extensions for \'C\' style source and
header files. \'C\' code is discouraged.

**Guideline 22** - Any procedural code written should be compiled in
C++.

> Rationale: C++ compilers provide much stricter type checking than C
> compilers. The stronger type checking is well worth using, even if the
> code does not take advantage of the object oriented features of C++.

**Guideline 23 -** Name directories like nested structures.

# 6. Usage

**Guideline 24** - There are no circumstances where goto is allowed.

**Guideline 25** - Avoid deep nesting of statements, parentheses, and
structures.

**Guideline 26** - All assignments shall stand alone, unless a series of
variables are being assigned to the same value.

**Standard 50** - Do not use comparisons in mathematical expressions.
```
    numberOfDays = ( isLeapYear() == TRUE ) + 28; // not OK
```
**Guideline 27** - All non-boolean comparison expressions should use a
comparison operator. Do not use implicit ! = 0.
```
    REQUIRE( aObjectPtr != NULLPTR ); // good
    REQUIRE( aObjectPtr ); // bad
```
**Guideline 28** - Avoid assignment in comparisons, except where the
alternative is significantly more complex.

**Standard 51** - Use explicit casting, instead of the compiler default.
```
    Dword aUnsignedValue(0);
    Real 	aRealValue(3.7);
    aBigValue = Dword(aRealValue);
```
Also note that the class operator overloads should be used as a
preference for upcasting and downcasting:
```
    class Foo
    {
    public:
    	//
    	// Accessor
    	//
    	operator Dword( void ) const
    	{
    		return Dword( m_Value );
    	}
    	operator Short( void ) const
    	{
    		return Short( m_Value );
    	}
    	//
    	// Mutator
    	//
    protected:
    	Real m_Value;
    };
```
**Guideline 29** - Default to pre-increment and pre-decrement unless the
post-increment/decrement operators are logically necessary.

**Guideline 30 -** Minimize negative comparisons.

**Guideline 32** - Minimize use of the comma operator.

## 6.1. Conditionals

**Guideline 33** - Use if (cond) . . . else rather than conditional
expressions ( (cond) ? : ) if only to clarify the intended operation.

**Guideline 34** - Use nested if only to clarify the intended order of
evaluation.
```
    if ( foo() == true )
    {
    	if ( bar() == true )
    	{
    	}
    }
```
*- VERSUS -*
```
    if ( foo() && bar() )
    {
    }
```
**Standard 52** - In a switch statement, make all cases independent by
using break at the end of each. All switch statements should have a
default. This is also true for if\...else if\...else blocks.

**Standard 53** Use if\...else for two alternative actions. Put the
major action first.

## 6.2. Loop Constructs

**Guideline 35** - Count for loops in ascending.

**Standard 54** - Use for loops when the loop control needs initializing
or recalculating; otherwise, use while.

**Standard 55** - Use while( 1 ) to implement an infinite loop. Make its
usage clear with comments.

**Guideline 36 -** Be careful with the logic of do loops. Use
do\...while( !(\...) ) to loop until a comparison becomes true.

**Guideline 37** - Minimize use of break in loops. Only use it for
abnormal escape.

**Guideline 38** - Use continue sparingly. Clearly comment why continue
is used.

3# 6.3. Data

**Standard 56** - Use NULLPTR with pointers only. ( \#define NULLPTR 0
should declared in types.hpp ).

**Guideline 39** - Use RTTI where appropriate.

Rationale: The developer may not want to compile with RTTI for whatever
reason. You should consider using templates if type reasoning is
required. On the other hand, RTTI is part of the C++ 14882 (1998E)
standard.

**Guideline 40** - Beware of operations with constants going out of
range.

**Standard 57** - Use single-quoted characters for character constants,
but never single-quote more than one character (or hex for
non-printing).

**Standard 58** - Use sizeof rather than a constant.

**Standard 59** - Do not compare floating-point numbers for equality.

**Standard 60** - Assign to all data members in operator=.

**Standard 61** - Check for assignment to this in operator=. If
assignment to this is attempted, simply return from the function.
```
    MyClassRef MyClass::operator=( MyClassCref aRef )
    {
    	if ( this != &aRef )
    	{
    		// do the assignment
    		...
    	}
    	else
    	{
    		...
    	}

    	return *this;
    }
```
**Standard 62** - Make sure operator= invokes any parents\' operator=,
except with virtual inheritance.

## 6.4. Constructors and Destructor

**Standard 63** - Always define a default and copy constructor as well
as an assignment operator for a class. Make these functions private if
they should not be used.

Rationale: The compiler will create these for you if you don\'t. It is
the side effects and tracking down of such that is avoided with
explicitly defining them.

**Guideline 41** - Prefer assignment in constructor over initialization.
```
    MyClass::MyClass( void )
    {
    	theAlpha = 0;
    	theBeta = 0;
    	theGamma = 0;
    }
```
*- INSTEAD OF -*
```
    MyClass::MyClass( void ) :
    	theAlpha(0),
    	theBeta(0),
    	theGamma(0)
    {
    	...
    }
```
**Standard 64** - Make destructor virtual in all polymorphic classes, or
classes where the potential is high.

**Standard 65** - A constructor should put its object in a well-defined
state. At the end of the constructor, the object must satisfy its class
invariant.

**Standard 66** - A constructor that fails shall throw an exception.

## 6.5. Initialization

**Standard 67** - Explicitly initialize static data.

**Standard 68** - Initialize all variables at the time they are declared
to the appropriate value. If the value is not yet known, initialize
pointers to NULLPTR and simple types to zero.

**Standard 69** - List members in a constructor initialization list in
order in which they are declared in the class header.

## 6.6. Declaration

**Guideline 42** - All data should be defined toward the top of a
function.

**Standard 70** - Use floating-point numbers only where necessary.

**Standard 71** - Do not use global data. Consider putting global
information in the context of a static class.

## 6.7. Programming

**Guideline 43** - Make sure interface definitions are clear and
sufficient.

**Guideline 44** - Defend against system, program and user errors. Heavy
use of assertions and exceptions are encouraged.

**Guideline 45** - Enable the user and the maintainer to find sufficient
information to understand an error. Include enough diagnostic
information to give an accurate picture of why the error occurred.

**Guideline 46** - Do not use arbitrary, predefined limits ( e.g. on
symbol table entries, user names,

file names).

**Guideline 47** - Make code more testable by reducing complexity.

**Standard 72 -** When coding, use exactly the same names as in the
object model.

**Standard 73 -** Use the same form in corresponding calls to new and
delete (i.e. new Foo uses delete FooPtr and new Foo\[ 100 \] uses delete
\[\] FooArray.)

**Guideline 48** - Know what C++ silently creates and calls (e.g.
default constructor, copy constructor, assignment operator, address-of
operators(const and not), and the destructor for a derived class where
the base class\'s destructor is defined.)

**Standard 73** - Ensure that objects (both simple and class) are
initialized before they are used.

**Standard 74 -** Eradicate all compiler warnings. Any unavoidable
warnings must be explicitly commented in the code. Unavoidable compiler
warnings should be extremely rare.

## 6.8. Class and Functions

**Guideline 49** - Strive for class interfaces that are complete and
minimal.

**Guideline 50** - The programmer should only have to look at the .hpp
file to use a class.

**Standard 75** - Do not put data members in the public interface.

**Standard 76** - Pass and return objects be reference instead of value
whenever possible.

**Standard 77** - If the passed object is not going to be modified then
pass it as a const reference.

**Standard 78** - The keyword class will appear in the left most column.
If declaring the class in the scope of a namespace, then class will be
indented appropriately.

**Standard 79** - The member access controls appear flush with the class
keyword.

**Standard 80** - Access controls that have no members may be omitted.

**Standard 81** - Access controls appear in the following order
```
    public: 		// Public method declarations
    protected: 	// Protected method declarations
    private: 	// Private method declarations
    protected: 	// Protected class data members
    private: 	// Private class data members
```
*comments here are for clarification.*

**Standard 82** The virtual or static declarations appear in the first
indentation level from the class declaration.

**Standard 83** - The return type of a class method or the storage type
of a class data member appear after the first tab position beyond the
space were virtual applied.

**Standard 84** Method identifiers follow the return type and should be
reasonably lined with other method declarations.

**Standard 85** - In each access control group for methods, Constructors
are followed by destructor, followed by operator overloads, followed by
accessors followed by mutators.
```
    class MyClass
    {
    public:
    	// Default constructor
    	MyClass( void )

    	// Copy constructor
    	// \param Object constant reference
    	MyClass( ObjectCref );

    	// Destructor
    	virtual ~MyClass( void );

    	// Equality operator overload
    	// \param MyClass constant reference
    	// \returns bool - true if equal, false otherwise
    	bool operator==( MyClassCref );

    	//
    	// Accessors
    	//
    	
    	// Get the number of MyClass instantiations.
    	// \returns Int const reference to count
    	*/
    	static IntCref getInstanceCount( void );

    	
    	// Return the object data member
    	// \returns Object const reference
    	ObjectCref getObject( void ) const;

    	//
    	// Mutators
    	//

    	// Sets the something thing
    	// \param Something const reference
    	virtual void setSomething( SomethingCref );

    protected:
    	// Copy never allowed
    	MyClass( MyClassCref ) throw(Assertion)
    	{
    		...
    	}

    	// Assignment operator denied
    	MyClassRef operator=( MyClassCref ) throw(Assertion)
    	{
    		...
    		return *this;
    	}
    private:
    	// No private methods
    protected:
    	// No protected data members
    private:
    	/// Class instance counter
    	static Int theInstanceCount;
    };
```
**Guideline 51** - Don\'t return a reference, or pointer, when you must
return an object, and don\'t return an object when you mean a reference.

**Guideline 52** - Avoid overloading on a pointer and a numerical type.
(i.e. foo( char \* ) vs. foo( int ) { a call to foo( 0 ) is ambiguous).

**Guideline 53** - Use static classes to partition the global namespace.
(dated with C++ namespace )

**Standard 86** - Do not return handles to internal data from const
member functions. If a handle must be returned, make it const.

**Standard 87** - Avoid member functions that return pointers or
references to members less accessible

than themselves. Use const!

**Standard 88** Never return a reference to a local object or a
de-referenced pointer initialized by new within the function.

Rationale: Obviously, when a function ends, the local object goes out of
scope, and the reference is no longer valid. One might attempt to NEW
the object in the function instead, but then who would call the
corresponding DELETE?

**Standard 89** - Use enums for integral class constants.

**Guideline 54 -** Use inlining judiciously.

**Guideline 55** - Inlines cause code bloat, slow down compile times,
eat up name space, and not all compilers handle them the same way.

## 6.9. Templates and Template Functions

As per sourceware.cygnus.com with the standards in this guide applied

**Standard 90** - Template function indentation should follow the form
```
    template<class T> void doSomethingFunction( args )
    {
    	//
    }
```
*- NOT -*
```
    template<class T> void template_function( args ) {};
```
Rationale: In class definitions, without indentation white space is
needed both above and below the declaration to distinguish it visually
from other members.

**Standard 91** Template class indentation should follow the form with
what is not shown following the Section 6.8 on page 20.
```
    template<class T> class Base 
    {
    public: // Types:
    };
```
*- NOT-*
```
    template<class T> class Base { public: // Types:
    };
```
## 6.10. Inheritance

**Guideline 56** - Make sure public inheritance models \'is-a\'.

**Guideline 57** Differentiate between inheritance of the interface and
of the implementation, and prefer delegation to implementation
inheritance.

Rationale: Inheritance of the interface only is forced by making a
function pure virtual-its implementation must be defined by the derived
class. Inheritance of implementation occurs when the function is
declared as simple virtual-derived classes may or may not override the
implementation.

**Standard 92 -** Never redefine an inherited non-virtual function.

**Standard 93** - Never redefine an inherited default parameter value.

**Standard 94** - A virtual function cannot strengthen a pre-condition
or weaken a postcondition. Use the BASE\_INVARIANT in the INVARIANT of
the derived class.

**Guideline 58** - Use private inheritance judiciously.

**Guideline 59** - Differentiate between inheritance and templates.

Rationale: If the type of the object being manipulated does not affect
the behavior or the class, then a template will do. However, if the type
of the object DOES affect the behavior, then virtual functions should be
used through inheritance.

## 6.11. Object-Oriented Considerations

**Standard 95** - Factor our common code into an ancestor.

**Guideline 60** - Encapsulate external code within an operation or
class.

**Guideline 61** - Keep member functions small, coherent and consistent.

**Guideline 62** - Separate policy member functions (e.g. error and
status checkers) from implementation member functions (computational).

**Standard 96** - Do not use indirect function calls unless absolutely
necessary.

**Standard 97 -** Write member functions for all combinations of input
conditions. Avoid using modes to distinguish between conditions. Use
member function overloading instead.

**Standard 98 -** Avoid case statements on object type; use member
functions instead.

**Standard 99** - Keep internal class structure hidden from other
classes. Do not use global or public data.

**Standard 100 -** Do not traverse multiple links or member functions in
a single statement. Invoke each member function via a temporary pointer
or reference.

**Standard 101** - Use const wherever a function, parameter or return
value will not change.

**Guideline 63** - All accessor functions should be const.

## 6.12. Error Handling

**Standard 102** - Use exceptions rather than returning a failure
status.

**Standard 103 -** Use assertions liberally.

**Standard 104** - Derived classes must maintain the base class\'s
invariant. This is to be verified by a call to

## 6.13. Exception Specification

**Standard 105 -** Exceptions are to be specified in the signature of a
class method declaration and definition.

**Standard 106** - Exception type hierarchies should be created which
reflect the domain.

Rationale: It is easier to reason with an Exception type rather than
figuring out what the exception was through a text message.
```
    class Bridge : public CoreLinuxObject 
    {
    public:
    	/**
    	Bridge assignment operator
    	@param Bridge constant reference
    	@return Reference to *this
    	@exception Exception
    	*/
    	BridgeRef operator=( BridgeCref ) throw(Exception);
    };

    //
    // can't be reasoned with compared to:
    //
    class BridgeException : public Exception {..};

    class Bridge : public CoreLinuxObject
    {
    public:
    	/**
    	Bridge assignment operator
    	@param Bridge constant reference
    	@return Reference to *this
    	@exception BridgeException
    	*/
    	BridgeRef operator=( BridgeCref ) throw(BridgeException);
    };

    //
    // at a minimum, and
    //
    class BridgeException : public Exception {..};

    class SetImplementationException : public BridgeException {..};

    class Bridge : public CoreLinuxObject
    {
    public:
    	/**
    	Bridge assignment operator
    	@param Bridge constant reference
    	@return Reference to *this
    	@exception SetImplementationException
    	*/
    	BridgeRef operator=( BridgeCref ) throw(SetImplementationException);
    };

    //
    // being the most useful
    //
```
# 7. File Layout

**Guideline 64** - Use functional cohesion to group similarly items.

**Guideline 65** Source files may be split up along boundaries between
class administrator, accessor, mutator and provider functions.

**Standard 107 -** A class shall have a single header file.

**Guideline 66** - Lay out data files to reflect the systems they serve.

**Standard 108** - Do not reserve memory in header files.

**Standard 109** Minimize header file interdependence.

**Guideline 67** - Keep function length in code files to within one or
two pages (100 lines).

**Guideline 68** - Keep modules small. Each module should be
functionally cohesive and should be as small as possible. Modules should
not exceed 10-15 pages in length.

**Guideline 69** - Classes with a large number of functions should break
the implementation into several .CPP files. These files should be
functionally cohesive.

# 8. Header File Layout

**Standard 110** - All headers must be wrapped to prevent multiple
inclusion.
```
    #if !defined(MYHEADER_HPP)
    #define MYHEADER_HPP
    ...
    #endif /* MYHEADER_HPP */
```
*- OR -*
```
    #if !defined(MYHEADER_HPP)
    #define MYHEADER_HPP
    ...
    #endif /* MYHEADER_HPP */
```
**Standard 111 -** public, protected and private line appear between
column 1 and 3 inclusive within a class definition.

**Standard 112** - Types, returns, member names, functions must be lined
up consistently in header.

**Standard 113** - Trailing comments must be aligned within the module.

# 9. Special Care and Handling

In some cases, you may need to handle situations where a conflict arises
between the use of both your class and header files, and installed
system or third-party files. This may result in either failed
compilation or run-time library resolution problems.

**Guideline 70** - Order system, or third party, includes before local
header files.

**Guideline 71** - Make use of namespaces defined by the provider.

**Standard 114 --** Do not include \#ifdef operating system into include
files.

This pollutes the include files and makes them unreadable.

Instead of code like this:
```
    	#ifdef WINDOWS
    		…
    	#elif OSX
    		…
    	#endif
```
Use this
```
    	#include “Platform.h”
```
Which will contain the includes/defines for a particular OS. This also
has the added benefit of using fast precompiled headers that speed up
the build process.

And then setup the solution/make/cmake files to include per operating
system include directories like this:
```
    Windows.mk

    $(INCLUDE) = “platform/windows/”

    Android.mk

    $(INCLUDE) = “platform/android/”
```
# 10. References

The Corelinux Consortium. The Corelinux C++ Coding Standards. The
Corelinux Consortium, 1.6 edition, May 2000a. <http://corelinux.sourceforge.net/cppstnd.php>\
Erich Gamma, et. Al. Design Patters -- Elements of Reusable Object-Oriented Software. Addison Wesley, Boston, MA, 1995 \
Alan Shalloway. Design Patterns Explained. Addison Wesley, Boston, MA. 2002


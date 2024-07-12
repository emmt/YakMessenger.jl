# Things to do

Publish the port of the server in a readable file.

Implement a minimally secure connection system.

Evaluate the command in a *safe* environment. For example, in Yorick:

```.c
func _yak_eval_func(_yak_arg)
{
    rename = remove = system = open = rmdir = mkdir = [];
    return _yak_eval_expr;
}
```
